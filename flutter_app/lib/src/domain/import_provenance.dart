import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'note.dart';

enum ImportDecision {
  create,
  unchanged,
  update,
  keepLocal,
  conflict,
}

class ImportIdentity {
  const ImportIdentity({
    required this.source,
    required this.sourceInstance,
    required this.externalId,
  });

  final String source;
  final String sourceInstance;
  final String externalId;

  String get key => '$source\u0000$sourceInstance\u0000$externalId';

  void validate() {
    for (final value in [source, sourceInstance, externalId]) {
      if (value.trim().isEmpty ||
          value.length > 500 ||
          value.contains('\u0000')) {
        throw const FormatException('Identità import non valida.');
      }
    }
  }
}

class ImportDocument {
  const ImportDocument({
    required this.identity,
    required this.title,
    required this.body,
    required this.tags,
    required this.externalFingerprint,
    this.taskJson,
    this.targetIdHint,
  });

  final ImportIdentity identity;
  final String title;
  final String body;
  final List<String> tags;
  final String? taskJson;
  final String externalFingerprint;
  final String? targetIdHint;
}

class ImportRecord {
  const ImportRecord({
    required this.identity,
    required this.targetNoteId,
    required this.externalFingerprint,
    required this.localFingerprint,
    required this.lastBatchId,
    required this.importedAt,
    required this.lastSeenAt,
  });

  final ImportIdentity identity;
  final String targetNoteId;
  final String externalFingerprint;
  final String localFingerprint;
  final String lastBatchId;
  final int importedAt;
  final int lastSeenAt;

  Map<String, Object?> toMap() => {
        'source': identity.source,
        'sourceInstance': identity.sourceInstance,
        'externalId': identity.externalId,
        'targetNoteId': targetNoteId,
        'externalFingerprint': externalFingerprint,
        'localFingerprint': localFingerprint,
        'lastBatchId': lastBatchId,
        'importedAt': importedAt,
        'lastSeenAt': lastSeenAt,
      };

  factory ImportRecord.fromMap(Map<String, Object?> row) => ImportRecord(
        identity: ImportIdentity(
          source: row['source']?.toString() ?? '',
          sourceInstance: row['sourceInstance']?.toString() ?? '',
          externalId: row['externalId']?.toString() ?? '',
        ),
        targetNoteId: row['targetNoteId']?.toString() ?? '',
        externalFingerprint: row['externalFingerprint']?.toString() ?? '',
        localFingerprint: row['localFingerprint']?.toString() ?? '',
        lastBatchId: row['lastBatchId']?.toString() ?? '',
        importedAt: (row['importedAt'] as num?)?.toInt() ?? 0,
        lastSeenAt: (row['lastSeenAt'] as num?)?.toInt() ?? 0,
      );
}

class ImportResolution {
  const ImportResolution({
    required this.decision,
    required this.localFingerprint,
  });

  final ImportDecision decision;
  final String? localFingerprint;
}

class ImportSummary {
  const ImportSummary({
    this.created = 0,
    this.updated = 0,
    this.unchanged = 0,
    this.keptLocal = 0,
    this.conflicts = 0,
    this.skipped = 0,
  });

  final int created;
  final int updated;
  final int unchanged;
  final int keptLocal;
  final int conflicts;
  final int skipped;

  int get total =>
      created + updated + unchanged + keptLocal + conflicts + skipped;

  Map<String, Object?> toMap() => {
        'created': created,
        'updated': updated,
        'unchanged': unchanged,
        'keptLocal': keptLocal,
        'conflicts': conflicts,
        'skipped': skipped,
      };

  ImportSummary add(ImportDecision decision) => ImportSummary(
        created: created + (decision == ImportDecision.create ? 1 : 0),
        updated: updated + (decision == ImportDecision.update ? 1 : 0),
        unchanged: unchanged + (decision == ImportDecision.unchanged ? 1 : 0),
        keptLocal: keptLocal + (decision == ImportDecision.keepLocal ? 1 : 0),
        conflicts: conflicts + (decision == ImportDecision.conflict ? 1 : 0),
        skipped: skipped,
      );

  ImportSummary addSkipped() => ImportSummary(
        created: created,
        updated: updated,
        unchanged: unchanged,
        keptLocal: keptLocal,
        conflicts: conflicts,
        skipped: skipped + 1,
      );

  String userLabel() =>
      'Creati $created · aggiornati $updated · invariati $unchanged · '
      'locali mantenuti $keptLocal · conflitti $conflicts'
      '${skipped == 0 ? '' : ' · saltati $skipped'}';
}

abstract final class ImportProvenance {
  static String fingerprint({
    required String title,
    required String body,
    required List<String> tags,
    String? taskJson,
  }) {
    final normalizedTags = [...tags.map((tag) => tag.trim().toLowerCase())]
      ..sort();
    final canonical = jsonEncode({
      'title': title.replaceAll('\r\n', '\n').trim(),
      'body': body.replaceAll('\r\n', '\n').trim(),
      'tags': normalizedTags,
      'taskJson': taskJson?.trim(),
    });
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static String fingerprintNote(Note note) => fingerprint(
        title: note.title,
        body: note.body,
        tags: note.tags,
        taskJson: note.taskJson,
      );

  static ImportResolution resolve({
    required ImportDocument document,
    required ImportRecord? record,
    required Note? local,
  }) {
    document.identity.validate();
    if (record == null || local == null || local.isDeleted) {
      return const ImportResolution(
        decision: ImportDecision.create,
        localFingerprint: null,
      );
    }

    final currentLocal = fingerprintNote(local);
    final externalChanged =
        document.externalFingerprint != record.externalFingerprint;
    final localChanged = currentLocal != record.localFingerprint;

    if (!externalChanged && !localChanged) {
      return ImportResolution(
        decision: ImportDecision.unchanged,
        localFingerprint: currentLocal,
      );
    }
    if (externalChanged && !localChanged) {
      return ImportResolution(
        decision: ImportDecision.update,
        localFingerprint: currentLocal,
      );
    }
    if (!externalChanged && localChanged) {
      return ImportResolution(
        decision: ImportDecision.keepLocal,
        localFingerprint: currentLocal,
      );
    }
    return ImportResolution(
      decision: ImportDecision.conflict,
      localFingerprint: currentLocal,
    );
  }
}
