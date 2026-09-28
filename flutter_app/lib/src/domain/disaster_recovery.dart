import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'attachments.dart';
import 'backup.dart';
import 'blocks.dart';
import 'derivatives.dart';
import 'documents.dart';
import 'import_provenance.dart';
import 'project_workspace.dart';
import 'properties.dart';
import 'research.dart';
import 'shared_spaces.dart';
import 'study.dart';
import 'workflow_automation.dart';

class DisasterRecoveryPreview {
  const DisasterRecoveryPreview({
    required this.snapshot,
    required this.revisions,
    required this.blocks,
    required this.properties,
    required this.knowledge,
    required this.derivatives,
    required this.projects,
    required this.study,
    required this.documents,
    required this.importProvenance,
    this.automations = const {
      'version': 1,
      'rules': <Object?>[],
      'runs': <Object?>[],
    },
    required this.sharedSpaces,
    required this.assets,
    required this.createdAt,
  });

  final BackupSnapshot snapshot;
  final List<Map<String, Object?>> revisions;
  final List<ContentBlock> blocks;
  final Map<String, Object?> properties;
  final Map<String, Object?> knowledge;
  final Map<String, Object?> derivatives;
  final Map<String, Object?> projects;
  final Map<String, Object?> study;
  final Map<String, Object?> documents;
  final Map<String, Object?> importProvenance;
  final Map<String, Object?> automations;
  final SharedSpacesSnapshot sharedSpaces;
  final Map<String, Uint8List> assets;
  final int createdAt;
}

abstract final class DisasterRecoveryBundle {
  static const format = 'notes-disaster-recovery';
  static const version = 2;
  static const legacyVersion = 1;
  static const maxArchiveBytes = 96 * 1024 * 1024;
  static const maxExpandedBytes = 128 * 1024 * 1024;
  static const maxJsonBytes = 12 * 1024 * 1024;
  static const maxEntries = 12050;

  static Future<Uint8List> encode({
    required BackupSnapshot snapshot,
    required List<Map<String, Object?>> revisions,
    required List<ContentBlock> blocks,
    required Map<String, Object?> properties,
    required Map<String, Object?> knowledge,
    required Map<String, Object?> derivatives,
    required Map<String, Object?> projects,
    required Map<String, Object?> study,
    required Map<String, Object?> documents,
    required Map<String, Object?> importProvenance,
    Map<String, Object?> automations = const {
      'version': 1,
      'rules': <Object?>[],
      'runs': <Object?>[],
    },
    required SharedSpacesSnapshot sharedSpaces,
    required AttachmentStore store,
    int? createdAt,
  }) async {
    final assets = <String, Uint8List>{};
    for (final key in _referencedAssets(
      snapshot,
      derivatives: derivatives,
      documents: documents,
    )) {
      final bytes = await store.read(key);
      Attachments.verify(key, bytes);
      assets[key] = bytes;
    }
    return encodeLoaded(
      snapshot: snapshot,
      revisions: revisions,
      blocks: blocks,
      properties: properties,
      knowledge: knowledge,
      derivatives: derivatives,
      projects: projects,
      study: study,
      documents: documents,
      importProvenance: importProvenance,
      automations: automations,
      sharedSpaces: sharedSpaces,
      assets: assets,
      createdAt: createdAt,
    );
  }

  static Uint8List encodeLoaded({
    required BackupSnapshot snapshot,
    required List<Map<String, Object?>> revisions,
    required List<ContentBlock> blocks,
    required Map<String, Object?> properties,
    required Map<String, Object?> knowledge,
    required Map<String, Object?> derivatives,
    required Map<String, Object?> projects,
    required Map<String, Object?> study,
    required Map<String, Object?> documents,
    required Map<String, Object?> importProvenance,
    Map<String, Object?> automations = const {
      'version': 1,
      'rules': <Object?>[],
      'runs': <Object?>[],
    },
    required SharedSpacesSnapshot sharedSpaces,
    required Map<String, Uint8List> assets,
    int? createdAt,
  }) {
    BackupCodec.validate(snapshot);
    _validateRevisions(revisions, snapshot);
    _validateBlocks(blocks, snapshot);
    SharedSpacesCodec.encode(sharedSpaces);

    final referenced = _referencedAssets(
      snapshot,
      derivatives: derivatives,
      documents: documents,
    );
    if (assets.length != referenced.length ||
        !assets.keys.toSet().containsAll(referenced) ||
        !referenced.containsAll(assets.keys)) {
      throw const FormatException(
        'Allegati non coerenti con lo stato da salvare.',
      );
    }

    final payloads = <String, Uint8List>{
      'backup.json': _jsonBytes(jsonDecode(BackupCodec.encode(snapshot))),
      'revisions.json': _jsonBytes({'version': 1, 'items': revisions}),
      'blocks.json': _jsonBytes({
        'version': 1,
        'items': blocks.map((block) => block.toMap()).toList(growable: false),
      }),
      'properties.json': _jsonBytes(properties),
      'knowledge.json': _jsonBytes(knowledge),
      'derivatives.json': _jsonBytes(derivatives),
      'projects.json': _jsonBytes(projects),
      'study.json': _jsonBytes(study),
      'documents.json': _jsonBytes(documents),
      'imports.json': _jsonBytes(importProvenance),
      'automations.json': _jsonBytes(automations),
      'shared-spaces.json': Uint8List.fromList(
        utf8.encode(SharedSpacesCodec.encode(sharedSpaces)),
      ),
    };
    for (final entry in assets.entries) {
      Attachments.verify(entry.key, entry.value);
      payloads['assets/${entry.key}'] = entry.value;
    }

    var expanded = 0;
    final files = <String, Object?>{};
    for (final entry in payloads.entries) {
      expanded += entry.value.length;
      if (expanded > maxExpandedBytes) {
        throw const FormatException(
          'Il backup di ripristino supera il limite espanso.',
        );
      }
      files[entry.key] = {
        'bytes': entry.value.length,
        'sha256': sha256.convert(entry.value).toString(),
      };
    }

    final created = createdAt ?? DateTime.now().millisecondsSinceEpoch;
    final manifest = _jsonBytes({
      'format': format,
      'version': version,
      'createdAt': created,
      'files': files,
    });

    final archive = Archive()
      ..add(ArchiveFile.bytes('manifest.json', manifest));
    for (final entry in payloads.entries) {
      archive.add(ArchiveFile.bytes(entry.key, entry.value));
    }

    final zip = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    if (zip.isEmpty || zip.length > maxArchiveBytes) {
      throw const FormatException(
        'Il backup di ripristino supera il limite consentito.',
      );
    }
    return zip;
  }

  static DisasterRecoveryPreview decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxArchiveBytes) {
      throw const FormatException(
        'Backup di ripristino vuoto o troppo grande.',
      );
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.isEmpty || archive.length > maxEntries) {
      throw const FormatException('Backup di ripristino non valido.');
    }

    final raw = <String, Uint8List>{};
    var expanded = 0;
    for (final entry in archive) {
      if (!entry.isFile || raw.containsKey(entry.name)) {
        throw const FormatException('Voce duplicata o non valida nel backup.');
      }
      final allowed = entry.name == 'manifest.json' ||
          entry.name == 'backup.json' ||
          entry.name == 'revisions.json' ||
          entry.name == 'blocks.json' ||
          entry.name == 'properties.json' ||
          entry.name == 'knowledge.json' ||
          entry.name == 'derivatives.json' ||
          entry.name == 'projects.json' ||
          entry.name == 'study.json' ||
          entry.name == 'documents.json' ||
          entry.name == 'imports.json' ||
          entry.name == 'automations.json' ||
          entry.name == 'shared-spaces.json' ||
          (entry.name.startsWith('assets/') &&
              Attachments.validKey(entry.name.substring('assets/'.length)));
      if (!allowed) {
        throw const FormatException('Percorso non consentito nel backup.');
      }
      final data = entry.readBytes();
      if (data == null) {
        throw const FormatException('Voce non leggibile nel backup.');
      }
      expanded += data.length;
      if (expanded > maxExpandedBytes) {
        throw const FormatException(
          'Il backup espanso supera il limite consentito.',
        );
      }
      raw[entry.name] = Uint8List.fromList(data);
    }

    final manifestBytes = raw.remove('manifest.json');
    if (manifestBytes == null || manifestBytes.length > 256 * 1024) {
      throw const FormatException('Manifest di ripristino mancante.');
    }
    final manifest = _map(
      jsonDecode(utf8.decode(manifestBytes, allowMalformed: false)),
      'manifest',
    );
    final bundleVersion = _integer(manifest['version'], 'version');
    if (manifest['format'] != format ||
        (bundleVersion != legacyVersion && bundleVersion != version)) {
      throw const FormatException(
        'Versione backup di ripristino non supportata.',
      );
    }
    final createdAt = _integer(manifest['createdAt'], 'createdAt');
    final declared = _map(manifest['files'], 'files');

    if (declared.length != raw.length ||
        !declared.keys.toSet().containsAll(raw.keys) ||
        !raw.keys.toSet().containsAll(declared.keys)) {
      throw const FormatException(
        'Manifest e contenuto del backup non coincidono.',
      );
    }

    for (final entry in raw.entries) {
      final info = _map(declared[entry.key], entry.key);
      final expectedBytes = _integer(info['bytes'], 'bytes');
      final expectedHash = info['sha256']?.toString() ?? '';
      if (expectedBytes != entry.value.length ||
          expectedHash != sha256.convert(entry.value).toString()) {
        throw FormatException(
          'Integrità non valida per ${entry.key}.',
        );
      }
      if (!entry.key.startsWith('assets/') &&
          entry.value.length > maxJsonBytes) {
        throw FormatException('${entry.key} supera il limite consentito.');
      }
    }

    final backupBytes = raw['backup.json'];
    if (backupBytes == null) {
      throw const FormatException('backup.json mancante.');
    }
    final snapshot = BackupCodec.decode(
      utf8.decode(backupBytes, allowMalformed: false),
    );
    final revisionsRoot = _jsonMap(raw, 'revisions.json');
    final blocksRoot = _jsonMap(raw, 'blocks.json');
    if (revisionsRoot['version'] != 1 || revisionsRoot['items'] is! List) {
      throw const FormatException('Revisioni backup non valide.');
    }
    if (blocksRoot['version'] != 1 || blocksRoot['items'] is! List) {
      throw const FormatException('Blocchi backup non validi.');
    }

    final revisions = (revisionsRoot['items'] as List)
        .map((value) => _map(value, 'revision'))
        .toList(growable: false);
    final blocks = (blocksRoot['items'] as List)
        .map((value) => ContentBlock.fromMap(_map(value, 'block')))
        .toList(growable: false);
    _validateRevisions(revisions, snapshot);
    _validateBlocks(blocks, snapshot);

    final assets = <String, Uint8List>{};
    for (final entry in raw.entries) {
      if (!entry.key.startsWith('assets/')) continue;
      final key = entry.key.substring('assets/'.length);
      Attachments.verify(key, entry.value);
      assets[key] = entry.value;
    }
    final sharedRaw = raw['shared-spaces.json'];
    if (sharedRaw == null) {
      throw const FormatException('Shared Spaces mancanti nel backup.');
    }

    final properties = _jsonMap(raw, 'properties.json');
    final knowledge = _jsonMap(raw, 'knowledge.json');
    final derivatives = _jsonMap(raw, 'derivatives.json');
    final projects = _jsonMap(raw, 'projects.json');
    final study = _jsonMap(raw, 'study.json');
    final documents = _jsonMap(raw, 'documents.json');
    final importProvenance = _jsonMap(raw, 'imports.json');
    final automations = bundleVersion >= 2
        ? _jsonMap(raw, 'automations.json')
        : <String, Object?>{
            'version': 1,
            'rules': <Object?>[],
            'runs': <Object?>[],
          };
    final referenced = _referencedAssets(
      snapshot,
      derivatives: derivatives,
      documents: documents,
    );
    if (referenced.length != assets.length ||
        !referenced.containsAll(assets.keys) ||
        !assets.keys.toSet().containsAll(referenced)) {
      throw const FormatException(
        'Allegati non coerenti con lo stato da ripristinare.',
      );
    }
    final sharedSpaces = SharedSpacesCodec.decode(
      utf8.decode(sharedRaw, allowMalformed: false),
    );
    _validateSidecars(
      snapshot: snapshot,
      properties: properties,
      knowledge: knowledge,
      derivatives: derivatives,
      projects: projects,
      study: study,
      documents: documents,
      importProvenance: importProvenance,
      automations: automations,
      sharedSpaces: sharedSpaces,
      assetKeys: assets.keys.toSet(),
    );

    return DisasterRecoveryPreview(
      snapshot: snapshot,
      revisions: revisions,
      blocks: blocks,
      properties: properties,
      knowledge: knowledge,
      derivatives: derivatives,
      projects: projects,
      study: study,
      documents: documents,
      importProvenance: importProvenance,
      automations: automations,
      sharedSpaces: sharedSpaces,
      assets: Map.unmodifiable(assets),
      createdAt: createdAt,
    );
  }

  static void _validateSidecars({
    required BackupSnapshot snapshot,
    required Map<String, Object?> properties,
    required Map<String, Object?> knowledge,
    required Map<String, Object?> derivatives,
    required Map<String, Object?> projects,
    required Map<String, Object?> study,
    required Map<String, Object?> documents,
    required Map<String, Object?> importProvenance,
    required Map<String, Object?> automations,
    required SharedSpacesSnapshot sharedSpaces,
    required Set<String> assetKeys,
  }) {
    final noteIds = snapshot.notes.map((note) => note.id).toSet();
    final sharedIds = sharedSpaces.spaces.map((space) => space.id).toSet();

    if (properties['version'] != 1 ||
        properties['definitions'] is! List ||
        properties['values'] is! List) {
      throw const FormatException('Proprietà recovery non valide.');
    }
    final definitions = (properties['definitions'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('Proprietà non valida.');
      final item = PropertyDefinition.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      PropertyRules.validateDefinition(item);
      return item;
    }).toList(growable: false);
    final definitionIds = definitions.map((item) => item.id).toSet();
    if (definitionIds.length != definitions.length) {
      throw const FormatException('Proprietà duplicate.');
    }
    for (final raw in properties['values'] as List) {
      if (raw is! Map) {
        throw const FormatException('Valore proprietà non valido.');
      }
      final item = NotePropertyValue.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (!noteIds.contains(item.noteId) ||
          !definitionIds.contains(item.definitionId)) {
        throw const FormatException('Riferimento proprietà non valido.');
      }
      final definition =
          definitions.firstWhere((value) => value.id == item.definitionId);
      PropertyRules.decodeValue(definition, item.valueJson);
    }

    if (knowledge['version'] != 1 ||
        knowledge['sources'] is! List ||
        knowledge['relations'] is! List ||
        knowledge['syncedBlocks'] is! List) {
      throw const FormatException('Knowledge recovery non valido.');
    }
    for (final raw in knowledge['sources'] as List) {
      if (raw is! Map) throw const FormatException('Fonte non valida.');
      final item = ResearchSource.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      ResearchRules.validateSource(item);
      if (!noteIds.contains(item.noteId)) {
        throw const FormatException('Fonte verso nota mancante.');
      }
    }
    for (final raw in knowledge['relations'] as List) {
      if (raw is! Map) throw const FormatException('Relazione non valida.');
      final item = NoteRelation.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (item.id.trim().isEmpty ||
          item.sourceId == item.targetId ||
          !noteIds.contains(item.sourceId) ||
          !noteIds.contains(item.targetId)) {
        throw const FormatException('Relazione verso nota mancante.');
      }
    }
    for (final raw in knowledge['syncedBlocks'] as List) {
      if (raw is! Map) throw const FormatException('Synced Block non valido.');
      final item = SyncedBlock.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (item.id.trim().isEmpty ||
          item.markdown.trim().isEmpty ||
          item.markdown.length > 200000) {
        throw const FormatException('Synced Block non valido.');
      }
    }

    if (derivatives['version'] != 1 || derivatives['derivatives'] is! List) {
      throw const FormatException('Derivati recovery non validi.');
    }
    for (final raw in derivatives['derivatives'] as List) {
      if (raw is! Map) throw const FormatException('Derivato non valido.');
      final item = SourceDerivative.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      if (!noteIds.contains(item.sourceNoteId) ||
          item.content.trim().isEmpty ||
          item.sourceFingerprint.trim().isEmpty ||
          item.engine.trim().isEmpty) {
        throw const FormatException('Derivato verso sorgente mancante.');
      }
    }

    if (projects['version'] != 1 ||
        projects['projects'] is! List ||
        projects['links'] is! List) {
      throw const FormatException('Progetti recovery non validi.');
    }
    final projectItems = (projects['projects'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('Progetto non valido.');
      final item = ProjectWorkspace.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      ProjectWorkspaceRules.validateProject(item);
      if (item.sharedSpaceId != null &&
          !sharedIds.contains(item.sharedSpaceId)) {
        throw const FormatException('Shared Space progetto mancante.');
      }
      return item;
    }).toList(growable: false);
    final projectIds = projectItems.map((item) => item.id).toSet();
    if (projectIds.length != projectItems.length) {
      throw const FormatException('Progetti duplicati.');
    }
    for (final raw in projects['links'] as List) {
      if (raw is! Map) throw const FormatException('Project link non valido.');
      final item = ProjectItemLink.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      ProjectWorkspaceRules.validateLink(item);
      if (!projectIds.contains(item.projectId) ||
          !noteIds.contains(item.noteId)) {
        throw const FormatException('Project link verso sorgente mancante.');
      }
    }

    if (study['version'] != 1 ||
        study['items'] is! List ||
        study['logs'] is! List) {
      throw const FormatException('Study recovery non valido.');
    }
    final learning = (study['items'] as List).map((raw) {
      if (raw is! Map) throw const FormatException('LearningItem non valido.');
      final item = LearningItem.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      StudyRules.validateItem(item);
      return item;
    }).toList(growable: false);
    final learningIds = learning.map((item) => item.id).toSet();
    if (learningIds.length != learning.length) {
      throw const FormatException('LearningItem duplicati.');
    }
    for (final raw in study['logs'] as List) {
      if (raw is! Map) throw const FormatException('ReviewLog non valido.');
      final item = ReviewLog.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      StudyRules.validateLog(item);
      if (!learningIds.contains(item.itemId)) {
        throw const FormatException('ReviewLog senza LearningItem.');
      }
    }

    if (documents['version'] != 1 || documents['annotations'] is! List) {
      throw const FormatException('Document recovery non valido.');
    }
    for (final raw in documents['annotations'] as List) {
      if (raw is! Map) throw const FormatException('Annotazione non valida.');
      final item = PdfAnnotation.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      DocumentRules.validateAnnotation(item);
      if (!noteIds.contains(item.noteId) ||
          !assetKeys.contains(item.assetKey) ||
          Attachments.type(item.assetKey) != AttachmentType.pdf) {
        throw const FormatException('Annotazione verso PDF mancante.');
      }
    }

    if (importProvenance['version'] != 1 ||
        importProvenance['records'] is! List ||
        importProvenance['batches'] is! List) {
      throw const FormatException('Provenance import recovery non valida.');
    }
    final recordKeys = <String>{};
    for (final raw in importProvenance['records'] as List) {
      if (raw is! Map) {
        throw const FormatException('Record provenance recovery non valido.');
      }
      final record = ImportRecord.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      record.identity.validate();
      if (!recordKeys.add(record.identity.key) ||
          !noteIds.contains(record.targetNoteId) ||
          record.externalFingerprint.length != 64 ||
          record.localFingerprint.length != 64 ||
          record.lastBatchId.trim().isEmpty ||
          record.importedAt < 0 ||
          record.lastSeenAt < 0) {
        throw const FormatException('Record provenance recovery non valido.');
      }
    }
    final batchIds = <String>{};
    for (final raw in importProvenance['batches'] as List) {
      if (raw is! Map) {
        throw const FormatException('Batch provenance recovery non valido.');
      }
      final id = raw['id']?.toString() ?? '';
      final source = raw['source']?.toString() ?? '';
      final sourceInstance = raw['sourceInstance']?.toString() ?? '';
      final startedAt = (raw['startedAt'] as num?)?.toInt() ?? -1;
      final completedAt = (raw['completedAt'] as num?)?.toInt();
      if (id.trim().isEmpty ||
          !batchIds.add(id) ||
          source.trim().isEmpty ||
          sourceInstance.trim().isEmpty ||
          startedAt < 0 ||
          (completedAt != null && completedAt < startedAt)) {
        throw const FormatException('Batch provenance recovery non valido.');
      }
    }
    if (automations['version'] != 1 ||
        automations['rules'] is! List ||
        automations['runs'] is! List) {
      throw const FormatException('Backup automazioni recovery non valido.');
    }
    final automationRules = (automations['rules'] as List).map((raw) {
      if (raw is! Map)
        throw const FormatException('Regola automazione non valida.');
      final rule = WorkflowRule.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      WorkflowAutomationRules.validateRule(rule);
      return rule;
    }).toList(growable: false);
    final automationRuleIds = automationRules.map((item) => item.id).toSet();
    if (automationRuleIds.length != automationRules.length ||
        automationRules.length > WorkflowAutomationRules.maxRules) {
      throw const FormatException('Regole automazione recovery non valide.');
    }
    final automationRunIds = <String>{};
    final automationRuns = automations['runs'] as List;
    if (automationRuns.length > WorkflowAutomationRules.maxRuns) {
      throw const FormatException(
          'Troppe esecuzioni automazione nel recovery.');
    }
    for (final raw in automationRuns) {
      if (raw is! Map) {
        throw const FormatException('Esecuzione automazione non valida.');
      }
      final run = WorkflowRun.fromMap(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      );
      WorkflowAutomationRules.validateRun(run);
      if (!automationRunIds.add(run.id) || !noteIds.contains(run.noteId)) {
        throw const FormatException(
            'Esecuzione automazione recovery non valida.');
      }
    }
  }

  static Set<String> _referencedAssets(
    BackupSnapshot snapshot, {
    Map<String, Object?> derivatives = const {},
    Map<String, Object?> documents = const {},
  }) {
    final keys = <String>{};
    for (final note in snapshot.notes) {
      if (!note.isVisual) {
        keys.addAll(Attachments.refs(note.body).map((ref) => ref.key));
      }
    }
    for (final draft in snapshot.drafts) {
      keys.addAll(Attachments.refs(draft.body).map((ref) => ref.key));
    }
    final derivativeRows = derivatives['derivatives'];
    if (derivativeRows is List) {
      for (final raw in derivativeRows.whereType<Map>()) {
        final key = raw['sourceAssetKey']?.toString();
        if (key != null && Attachments.validKey(key)) keys.add(key);
      }
    }
    final annotationRows = documents['annotations'];
    if (annotationRows is List) {
      for (final raw in annotationRows.whereType<Map>()) {
        final key = raw['assetKey']?.toString();
        if (key != null && Attachments.validKey(key)) keys.add(key);
      }
    }
    return keys;
  }

  static Map<String, Object?> _jsonMap(
    Map<String, Uint8List> raw,
    String name,
  ) {
    final bytes = raw[name];
    if (bytes == null) throw FormatException('$name mancante.');
    return _map(
      jsonDecode(utf8.decode(bytes, allowMalformed: false)),
      name,
    );
  }

  static Uint8List _jsonBytes(Object value) {
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
    if (bytes.length > maxJsonBytes) {
      throw const FormatException('Payload backup troppo grande.');
    }
    return bytes;
  }

  static Map<String, Object?> _map(Object? value, String name) {
    if (value is! Map) throw FormatException('$name non valido.');
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  static int _integer(Object? value, String name) {
    if (value is! num || value.toInt() != value || value.toInt() < 0) {
      throw FormatException('$name non valido.');
    }
    return value.toInt();
  }

  static void _validateRevisions(
    List<Map<String, Object?>> revisions,
    BackupSnapshot snapshot,
  ) {
    if (revisions.length > 500000) {
      throw const FormatException('Troppe revisioni nel backup.');
    }
    final noteIds = snapshot.notes.map((note) => note.id).toSet();
    final ids = <String>{};
    for (final row in revisions) {
      final revisionId = row['revisionId']?.toString() ?? '';
      final noteId = row['noteId']?.toString() ?? '';
      final title = row['title']?.toString() ?? '';
      final body = row['body']?.toString() ?? '';
      final tagsJson = row['tagsJson']?.toString() ?? '';
      final savedAt = row['savedAt'];
      if (revisionId.isEmpty ||
          !ids.add(revisionId) ||
          !noteIds.contains(noteId) ||
          title.length > 8000 ||
          body.length > 500000 ||
          tagsJson.length > 100000 ||
          savedAt is! num ||
          savedAt.toInt() < 0) {
        throw const FormatException('Revisioni backup non valide.');
      }
    }
  }

  static void _validateBlocks(
    List<ContentBlock> blocks,
    BackupSnapshot snapshot,
  ) {
    if (blocks.length > 1000000) {
      throw const FormatException('Troppi blocchi nel backup.');
    }
    final textNoteIds = snapshot.notes
        .where((note) => !note.isTask && !note.isVisual)
        .map((note) => note.id)
        .toSet();
    final ids = <String>{};
    for (final block in blocks) {
      ContentBlocks.validate(block);
      if (!ids.add(block.id) ||
          block.ownerType != 'note' ||
          !textNoteIds.contains(block.ownerId)) {
        throw const FormatException('Blocchi backup non validi.');
      }
    }
  }
}
