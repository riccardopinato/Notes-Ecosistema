import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Crash recovery for non-atomic multi-store restores.
///
/// The verified undo archive and its pending marker must both be durable
/// before any store mutation. A fully applied restore transitions the same
/// marker atomically to 'completed', instead of deleting an uncertain marker.
class RecoveryJournal {
  RecoveryJournal(
    this.directory, {
    Future<void> Function(Directory)? syncDirectory,
  }) : _syncDirectory = syncDirectory ?? _syncNativeDirectory;

  final Directory directory;
  final Future<void> Function(Directory) _syncDirectory;
  bool _completionBarrierUncertain = false;
  bool _completedBarrierChecked = false;

  static const MethodChannel _durabilityChannel =
      MethodChannel('notes.ecosystem/recovery_durability');

  static Future<void> _syncNativeDirectory(Directory directory) async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Ripristino distruttivo senza fsync della directory non supportato.',
      );
    }
    await _durabilityChannel.invokeMethod<void>(
      'fsyncDirectory',
      <String, String>{'path': directory.path},
    );
  }

  /// Flushes restored content-addressed attachment directory entries after
  /// AttachmentStore.put() renames and BEFORE the transaction may commit.
  /// The Android bridge rejects any path outside approved app-private stores.
  static Future<void> persistAttachmentDirectory(Directory directory) =>
      _syncNativeDirectory(directory);

  static const int maxSnapshotBytes = 96 * 1024 * 1024;
  static const int _version = 1;
  static const String _snapshotName = 'pre_restore.zip';
  static const String _markerName = 'pending.json';

  static Future<RecoveryJournal> open() async {
    final base = await getApplicationSupportDirectory();
    return RecoveryJournal(Directory(p.join(base.path, 'restore_journal')));
  }

  File get _snapshot => File(p.join(directory.path, _snapshotName));
  File get _marker => File(p.join(directory.path, _markerName));

  Future<Map<String, dynamic>?> _readMarker() async {
    if (!await _marker.exists()) return null;
    final raw = jsonDecode(await _marker.readAsString());
    if (raw is! Map<String, dynamic> ||
        raw['version'] != _version ||
        raw['length'] is! int ||
        raw['sha256'] is! String ||
        raw['phase'] is! String ||
        (raw['phase'] != 'pending' && raw['phase'] != 'completed') ||
        (raw['length'] as int) <= 0 ||
        (raw['length'] as int) > maxSnapshotBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256'] as String)) {
      throw const FormatException('Marker di recupero non valido.');
    }
    return raw;
  }

  /// Corrupt metadata is always a pending/error condition, never success.
  Future<bool> get hasPending async {
    try {
      final marker = await _readMarker();
      return marker != null && marker['phase'] == 'pending';
    } catch (_) {
      return true;
    }
  }

  Future<bool> get hasUnsettled async {
    final marker = await _readMarker();
    if (marker == null) return _completionBarrierUncertain;
    if (marker['phase'] == 'pending') return true;
    // A fresh journal instance MUST verify the completed marker's directory
    // fsync even if the rename is visible in the current OS page cache.
    if (!_completedBarrierChecked || _completionBarrierUncertain) {
      await _syncDirectory(directory);
      _completedBarrierChecked = true;
      _completionBarrierUncertain = false;
    }
    return false;
  }

  Future<void> begin(Uint8List verifiedSnapshot) async {
    if (await hasUnsettled) {
      throw const FormatException(
        'Esiste un ripristino interrotto: recuperalo prima di continuare.',
      );
    }
    if (verifiedSnapshot.isEmpty ||
        verifiedSnapshot.length > maxSnapshotBytes) {
      throw const FormatException('Snapshot di recupero fuori limite.');
    }

    await directory.create(recursive: true);
    // The native bridge also fsyncs the app-support ancestor directory.
    // The journal folder's own directory entry must survive power loss.
    await _syncDirectory(directory);

    // A durable 'completed' marker is safe to retire before a NEW restore.
    final previous = await _readMarker();
    if (previous != null) {
      if (previous['phase'] != 'completed') {
        throw const FormatException('Ripristino precedente non completato.');
      }
      await _marker.delete();
      await _syncDirectory(directory);
    }
    if (await _snapshot.exists()) {
      await _snapshot.delete();
      await _syncDirectory(directory);
    }

    final digest = sha256.convert(verifiedSnapshot).toString();
    final tempSnapshot = File(p.join(directory.path, 'pre_restore.tmp'));
    final tempMarker = File(p.join(directory.path, 'pending.tmp'));
    try {
      await tempSnapshot.writeAsBytes(verifiedSnapshot, flush: true);
      final reread = await tempSnapshot.readAsBytes();
      if (reread.length != verifiedSnapshot.length ||
          sha256.convert(reread).toString() != digest) {
        throw const FormatException('Snapshot locale non verificabile.');
      }
      await tempSnapshot.rename(_snapshot.path);
      await _syncDirectory(directory);

      final metadata = jsonEncode({
        'version': _version,
        'phase': 'pending',
        'length': verifiedSnapshot.length,
        'sha256': digest,
      });
      await tempMarker.writeAsString(metadata, flush: true);
      await tempMarker.rename(_marker.path);
      // No caller may begin writes until the marker and parent are durable.
      await _syncDirectory(directory);
    } finally {
      if (await tempSnapshot.exists()) await tempSnapshot.delete();
      if (await tempMarker.exists()) await tempMarker.delete();
    }
  }

  Future<Uint8List?> readPending() async {
    final marker = await _readMarker();
    if (marker == null || marker['phase'] == 'completed') return null;
    try {
      final bytes = await _snapshot.readAsBytes();
      if (bytes.length != marker['length'] ||
          sha256.convert(bytes).toString() != marker['sha256']) {
        throw const FormatException('Snapshot di recupero alterato.');
      }
      return Uint8List.fromList(bytes);
    } on FileSystemException {
      throw const FormatException(
        'Il recupero è bloccato: snapshot locale mancante.',
      );
    }
  }

  /// Called only after *every* store write of either candidate or rollback.
  /// Never delete the pending marker before its completed replacement is
  /// durably synchronized: ambiguous deletion could reopen unsafe app state.
  Future<void> complete() async {
    final marker = await _readMarker();
    if (marker == null || marker['phase'] != 'pending') {
      throw const FormatException('Nessuna transazione da completare.');
    }
    final temp = File(p.join(directory.path, 'completed.tmp'));
    try {
      await temp.writeAsString(
        jsonEncode({...marker, 'phase': 'completed'}),
        flush: true,
      );
      _completionBarrierUncertain = true;
      await temp.rename(_marker.path);
      await _syncDirectory(directory);
      _completionBarrierUncertain = false;
      _completedBarrierChecked = true;
    } finally {
      if (await temp.exists()) await temp.delete();
    }

    // Archive cleanup is not part of the commit barrier. An orphan is safe:
    // the durable completed marker prevents a stale rollback after reboot.
    try {
      if (await _snapshot.exists()) await _snapshot.delete();
    } on FileSystemException {
      // Best effort only.
    }
  }

  /// Retry a failed durability barrier without replaying completed data.
  Future<void> settleCompletionBarrier() async {
    await hasUnsettled;
  }
}

/// A single named sequence for the actual cross-store restore writes.
///
/// The outer RecoveryTransaction owns the durable journal/rollback. This
/// sequence makes every store phase explicit and test-injectable without
/// altering the real release's persistence or retry behavior.
abstract final class RecoveryWriteSequence {
  static const stages = <String>[
    'assets',
    'notes',
    'properties',
    'knowledge',
    'derivatives',
    'shared',
    'projects',
    'study',
    'documents',
    'imports',
    'automations',
  ];

  static Future<void> run(
    Map<String, Future<void> Function()> writes, {
    Future<void> Function(String stage)? afterStage,
  }) async {
    // Do not silently skip an archive or import sidecar during refactors.
    if (writes.length != stages.length ||
        stages.any((stage) => !writes.containsKey(stage))) {
      throw const FormatException('RECOVERY_WRITE_SEQUENCE_INCOMPLETE');
    }
    for (final stage in stages) {
      await writes[stage]!();
      // Only tests provide a failure hook; the production caller omits it.
      if (afterStage != null) await afterStage(stage);
    }
  }
}

abstract final class RecoveryTransaction {
  static Future<void> run({
    required RecoveryJournal journal,
    required Uint8List originalSnapshot,
    required Future<void> Function() applyCandidate,
    required Future<void> Function(Uint8List) applyOriginal,
  }) async {
    await journal.begin(originalSnapshot);
    try {
      await applyCandidate();
    } catch (error, stack) {
      try {
        final original = await journal.readPending();
        if (original == null) {
          throw const FormatException('Marker di recupero mancante.');
        }
        await applyOriginal(original);
        await journal.complete();
      } catch (_) {
        // A failed replay leaves the pending/uncertain journal for startup.
        Error.throwWithStackTrace(error, stack);
      }
      Error.throwWithStackTrace(error, stack);
    }
    // Commit-marker errors must NOT trigger a second rollback; the candidate
    // was fully applied. Fail closed until the marker's fsync is retried.
    await journal.complete();
  }

  static Future<bool> recoverPending({
    required RecoveryJournal journal,
    required Future<void> Function(Uint8List) applyOriginal,
  }) async {
    await journal.settleCompletionBarrier();
    final original = await journal.readPending();
    if (original == null) return false;
    await applyOriginal(original);
    await journal.complete();
    return true;
  }
}
