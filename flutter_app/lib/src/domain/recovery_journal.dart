import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A crash-resumable undo record for non-atomic multi-store restores.
///
/// The snapshot is written, flushed, and verified BEFORE the pending marker.
/// No caller may modify user stores until [begin] returns successfully.
/// The marker is removed only AFTER all store writes and checks have completed.
class RecoveryJournal {
  RecoveryJournal(this.directory);

  final Directory directory;

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

  Future<bool> get hasPending => _marker.exists();

  /// Fail closed if an earlier restore still needs recovery.
  Future<void> begin(Uint8List verifiedSnapshot) async {
    if (await hasPending) {
      throw const FormatException(
        'Esiste un ripristino interrotto: recuperalo prima di continuare.',
      );
    }
    if (verifiedSnapshot.isEmpty ||
        verifiedSnapshot.length > maxSnapshotBytes) {
      throw const FormatException('Snapshot di recupero fuori limite.');
    }
    await directory.create(recursive: true);

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
      final metadata = jsonEncode({
        'version': _version,
        'length': verifiedSnapshot.length,
        'sha256': digest,
      });
      await tempMarker.writeAsString(metadata, flush: true);
      // Only now does the durable marker authorize destructive writes.
      await tempMarker.rename(_marker.path);
    } finally {
      if (await tempSnapshot.exists()) await tempSnapshot.delete();
      if (await tempMarker.exists()) await tempMarker.delete();
    }
  }

  /// Null means no pending transaction. Corruption must NOT clear the marker.
  Future<Uint8List?> readPending() async {
    if (!await hasPending) return null;
    try {
      final raw = jsonDecode(await _marker.readAsString());
      if (raw is! Map<String, dynamic> ||
          raw['version'] != _version ||
          raw['length'] is! int ||
          raw['sha256'] is! String ||
          (raw['length'] as int) <= 0 ||
          (raw['length'] as int) > maxSnapshotBytes ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(raw['sha256'] as String)) {
        throw const FormatException('Marker di recupero non valido.');
      }
      final bytes = await _snapshot.readAsBytes();
      if (bytes.length != raw['length'] ||
          sha256.convert(bytes).toString() != raw['sha256']) {
        throw const FormatException('Snapshot di recupero alterato.');
      }
      return Uint8List.fromList(bytes);
    } on FileSystemException {
      throw const FormatException(
        'Il recupero è bloccato: snapshot locale mancante.',
      );
    }
  }

  /// Call only after a fully verified commit or rollback.
  Future<void> complete() async {
    if (!await hasPending) {
      throw const FormatException('Nessuna transazione da completare.');
    }
    // Delete the marker first: an orphaned snapshot is never a pending restore.
    await _marker.delete();
    if (await _snapshot.exists()) await _snapshot.delete();
  }
}

/// Coordinates an undo snapshot with the caller's canonical store writers.
///
/// On a normal failure, rollback is attempted immediately. A failed rollback
/// leaves the journal intact for startup retry; no silent success is returned.
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
      await journal.complete();
    } catch (error, stack) {
      try {
        final original = await journal.readPending();
        if (original == null) {
          throw const FormatException('Marker di recupero mancante.');
        }
        await applyOriginal(original);
        await journal.complete();
      } catch (_) {
        // Preserve the *original* failure and the pending marker for retry.
        Error.throwWithStackTrace(error, stack);
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  static Future<bool> recoverPending({
    required RecoveryJournal journal,
    required Future<void> Function(Uint8List) applyOriginal,
  }) async {
    final original = await journal.readPending();
    if (original == null) return false;
    await applyOriginal(original);
    await journal.complete();
    return true;
  }
}
