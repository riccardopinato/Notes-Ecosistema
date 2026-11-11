import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/note.dart';
import '../domain/workflow_automation.dart';

/// Local-only Web snapshot of the canonical Note/Task/Visual objects.
///
/// This is intentionally not a second Android database or a remote sync engine.
/// Browser local storage is origin/device specific and can be cleared by users.
/// Large media attachments and native integrations remain outside this v1 scope.
class WebWorkspaceSnapshot {
  const WebWorkspaceSnapshot({
    required this.notes,
    required this.collections,
    required this.rules,
    required this.runs,
  });

  factory WebWorkspaceSnapshot.empty() => const WebWorkspaceSnapshot(
        notes: [],
        collections: [],
        rules: [],
        runs: [],
      );

  final List<Note> notes;
  final List<NoteCollection> collections;
  final List<WorkflowRule> rules;
  final List<WorkflowRun> runs;

  WebWorkspaceSnapshot copyWith({
    List<Note>? notes,
    List<NoteCollection>? collections,
    List<WorkflowRule>? rules,
    List<WorkflowRun>? runs,
  }) =>
      WebWorkspaceSnapshot(
        notes: notes ?? this.notes,
        collections: collections ?? this.collections,
        rules: rules ?? this.rules,
        runs: runs ?? this.runs,
      );

  Map<String, Object?> toMap() => {
        'notes': [for (final note in notes) note.toMap()],
        'collections': [
          for (final collection in collections)
            {'id': collection.id, 'name': collection.name},
        ],
        'rules': [for (final rule in rules) rule.toMap()],
        'runs': [for (final run in runs) run.toMap()],
      };

  static WebWorkspaceSnapshot fromMap(Map<String, Object?> data) {
    List<T> readRows<T>(
      String key,
      T Function(Map<String, Object?>) decode,
    ) {
      final source = data[key];
      if (source is! List || source.length > 5000) {
        throw FormatException('Invalid Web workspace collection: $key');
      }
      return [
        for (final element in source)
          if (element is Map)
            decode(Map<String, Object?>.from(element))
          else
            throw FormatException('Invalid Web workspace item: $key'),
      ];
    }

    final notes = readRows('notes', Note.fromMap);
    final collections = readRows('collections', NoteCollection.fromMap);
    final rules = readRows('rules', WorkflowRule.fromMap);
    final runs = readRows('runs', WorkflowRun.fromMap);

    void uniqueIds(Iterable<String> ids, String label) {
      final seen = <String>{};
      for (final id in ids) {
        if (id.trim().isEmpty || id.length > 256 || !seen.add(id)) {
          throw FormatException('Duplicate or invalid $label identifier');
        }
      }
    }

    uniqueIds(notes.map((note) => note.id), 'note');
    uniqueIds(collections.map((item) => item.id), 'collection');
    uniqueIds(rules.map((item) => item.id), 'automation rule');
    uniqueIds(runs.map((item) => item.id), 'automation receipt');
    if (rules.length > 100 || runs.length > 500) {
      throw const FormatException('Unbounded Web automation snapshot');
    }
    return WebWorkspaceSnapshot(
      notes: notes,
      collections: collections,
      rules: rules,
      runs: runs,
    );
  }
}

/// Two-slot checksummed journal built on the existing shared_preferences Web
/// adapter (browser localStorage). This is suitable for bounded text-first
/// workspaces, not large archives or a full SQLite/IndexedDB replacement.
///
/// Each complete update is written to the alternate slot. The previous
/// acknowledged snapshot remains available if a write or checksum fails.
/// The new UI state is published only after a successful verified write.
class WebWorkspaceStore {
  WebWorkspaceStore(this._prefs);

  static const _keyA = 'notes.web.workspace.v1.a';
  static const _keyB = 'notes.web.workspace.v1.b';
  static const _schema = 1;

  // Conservative two-slot browser quota. The size applies to each encoded
  // snapshot, not to media/binary payloads (which are not supported here).
  static const maxSnapshotBytes = 750000;
  static const maxImportBytes = 900000;

  final SharedPreferences _prefs;
  int _sequence = 0;
  bool recoveredPrevious = false;

  /// Reload the browser backing store before first read. SharedPreferences
  /// caches values; another tab may have committed after this tab opened.
  Future<WebWorkspaceSnapshot> loadFresh() async {
    await _prefs.reload();
    return load();
  }

  WebWorkspaceSnapshot load() {
    final a = _prefs.getString(_keyA);
    final b = _prefs.getString(_keyB);
    recoveredPrevious = false;
    if (a == null && b == null) {
      _sequence = 0;
      return WebWorkspaceSnapshot.empty();
    }

    final valid = <_StoredWorkspace>[];
    for (final candidate in [a, b]) {
      if (candidate == null) continue;
      try {
        valid.add(_StoredWorkspace.decode(candidate));
      } on FormatException {
        recoveredPrevious = true;
      } on TypeError {
        recoveredPrevious = true;
      } on ArgumentError {
        recoveredPrevious = true;
      }
    }
    if (valid.isEmpty) {
      throw const FormatException(
        'Archivio Web non leggibile. Nessun dato è stato sovrascritto. '
        'Importa un backup valido prima di modificare lo spazio.',
      );
    }
    valid.sort((a, b) => a.sequence.compareTo(b.sequence));
    final current = valid.last;
    _sequence = current.sequence;
    return current.snapshot;
  }

  Future<void> save(WebWorkspaceSnapshot snapshot) async {
    // A snapshot must be decodable before it can become an acknowledged write.
    WebWorkspaceSnapshot.fromMap(snapshot.toMap());

    // A second tab may have changed the workspace since this instance loaded.
    // Reject stale writes rather than silently clobbering acknowledged data.
    final expectedSequence = _sequence;
    await _prefs.reload();
    final candidates = [
      _prefs.getString(_keyA),
      _prefs.getString(_keyB),
    ];
    final sequences = <int>[];
    for (final raw in candidates) {
      if (raw == null) continue;
      try {
        sequences.add(_StoredWorkspace.decode(raw).sequence);
      } on FormatException {
        // A corrupt alternate journal slot can be ignored if another is valid.
      } on ArgumentError {
        // Invalid persisted model fields must not be trusted.
      } on TypeError {
        // Invalid persisted model fields must not be trusted.
      }
    }
    if (sequences.isEmpty && candidates.any((raw) => raw != null)) {
      throw const FormatException('Nessuno snapshot browser integro');
    }
    final newest = sequences.isEmpty ? 0 : (sequences..sort()).last;
    if (newest != expectedSequence) {
      throw StateError(
        'Workspace modificato in un’altra scheda. '
        'Ricarica la pagina prima di salvare; nessuna modifica è stata applicata.',
      );
    }
    final sequence = _sequence + 1;
    final encoded = _StoredWorkspace.encode(snapshot, sequence);
    if (utf8.encode(encoded).length > maxSnapshotBytes) {
      throw StateError(
        'Spazio Web locale troppo grande. Esporta i dati: '
        'questa versione non gestisce archivi di grandi dimensioni.',
      );
    }
    final key = sequence.isOdd ? _keyA : _keyB;
    final written = await _prefs.setString(key, encoded);
    // Reading the SharedPreferences cache alone is not a persistence check.
    // A fresh read also detects a competing writer replacing this slot.
    await _prefs.reload();
    if (!written || _prefs.getString(key) != encoded) {
      throw StateError('Salvataggio browser non verificato.');
    }
    final receipt = _StoredWorkspace.decode(_prefs.getString(key)!);
    if (receipt.sequence != sequence) {
      throw StateError('Sequenza del salvataggio Web inattesa.');
    }
    _sequence = sequence;
    recoveredPrevious = false;
  }

  /// Explicit recovery after a valid, user-confirmed backup import.
  ///
  /// Ordinary saves still fail closed when both journal slots are corrupt.
  /// This operation never silently overwrites readable browser data.
  Future<void> recoverVerifiedBackup(WebWorkspaceSnapshot snapshot) async {
    WebWorkspaceSnapshot.fromMap(snapshot.toMap());
    final encoded = _StoredWorkspace.encode(snapshot, 1);
    if (utf8.encode(encoded).length > maxSnapshotBytes) {
      throw StateError('Backup troppo grande per lo spazio Web locale.');
    }
    await _prefs.reload();
    final candidates = [
      _prefs.getString(_keyA),
      _prefs.getString(_keyB),
    ];
    if (candidates.every((raw) => raw == null)) {
      throw StateError(
          'Archivio iniziale vuoto: usare il normale salvataggio.');
    }
    for (final raw in candidates) {
      if (raw == null) continue;
      try {
        _StoredWorkspace.decode(raw);
        throw StateError(
          'Esiste già una copia locale valida: ricarica la pagina '
          'prima di importare questo backup.',
        );
      } on FormatException {
        // Confirmed recovery deliberately ignores only unreadable slots.
      } on ArgumentError {
        // Invalid journal fields cannot be used to block safe recovery.
      } on TypeError {
        // Invalid journal fields cannot be used to block safe recovery.
      }
    }
    final written = await _prefs.setString(_keyA, encoded);
    await _prefs.reload();
    if (!written || _prefs.getString(_keyA) != encoded) {
      throw StateError('Scrittura di recupero non verificata.');
    }
    // The alternate slot is damaged, but deleting it must not delete A.
    // Never acknowledge recovery until the surviving slot is readable.
    final receipt = _StoredWorkspace.decode(_prefs.getString(_keyA)!);
    if (receipt.sequence != 1) {
      throw StateError('Sequenza di recupero Web inattesa.');
    }
    await _prefs.remove(_keyB);
    await _prefs.reload();
    if (_prefs.getString(_keyA) != encoded || _prefs.getString(_keyB) != null) {
      throw StateError('Pulizia del recupero Web non verificata.');
    }
    _sequence = 1;
    recoveredPrevious = false;
  }

  static String exportJson(WebWorkspaceSnapshot snapshot) {
    WebWorkspaceSnapshot.fromMap(snapshot.toMap());
    final payload = jsonEncode(snapshot.toMap());
    if (utf8.encode(payload).length > maxSnapshotBytes) {
      throw StateError('Il workspace supera il limite di export Web.');
    }
    return jsonEncode({
      'format': 'notes-web-workspace',
      'schema': _schema,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    });
  }

  static WebWorkspaceSnapshot importJson(String raw) {
    if (utf8.encode(raw).length > maxImportBytes) {
      throw const FormatException('Backup Web troppo grande');
    }
    final root = jsonDecode(raw);
    if (root is! Map ||
        root['format'] != 'notes-web-workspace' ||
        root['schema'] != _schema ||
        root['payload'] is! String ||
        root['sha256'] is! String) {
      throw const FormatException('Formato o schema di backup non supportato');
    }
    final payload = root['payload'] as String;
    final expected = sha256.convert(utf8.encode(payload)).toString();
    if (root['sha256'] != expected) {
      throw const FormatException('Checksum del backup non valido');
    }
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException('Snapshot non valido');
    }
    return WebWorkspaceSnapshot.fromMap(Map<String, Object?>.from(decoded));
  }
}

class _StoredWorkspace {
  const _StoredWorkspace(this.sequence, this.snapshot);
  final int sequence;
  final WebWorkspaceSnapshot snapshot;

  static String encode(WebWorkspaceSnapshot snapshot, int sequence) {
    final payload = jsonEncode(snapshot.toMap());
    return jsonEncode({
      'schema': 1,
      'sequence': sequence,
      'payload': payload,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
    });
  }

  static _StoredWorkspace decode(String raw) {
    // Untrusted browser data must be bounded before JSON parsing.
    if (utf8.encode(raw).length > WebWorkspaceStore.maxSnapshotBytes) {
      throw const FormatException('Web journal exceeds the allowed size');
    }
    final root = jsonDecode(raw);
    if (root is! Map ||
        root['schema'] != 1 ||
        root['sequence'] is! int ||
        (root['sequence'] as int) < 1 ||
        root['payload'] is! String ||
        root['sha256'] is! String) {
      throw const FormatException('Invalid local Web journal envelope');
    }
    final payload = root['payload'] as String;
    if (root['sha256'] != sha256.convert(utf8.encode(payload)).toString()) {
      throw const FormatException('Corrupt Web journal checksum');
    }
    final decoded = jsonDecode(payload);
    if (decoded is! Map) {
      throw const FormatException('Invalid Web journal snapshot');
    }
    return _StoredWorkspace(
      root['sequence'] as int,
      WebWorkspaceSnapshot.fromMap(Map<String, Object?>.from(decoded)),
    );
  }
}
