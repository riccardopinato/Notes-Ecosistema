import 'package:uuid/uuid.dart';

import '../domain/editing.dart';
import '../domain/import_provenance.dart';
import '../domain/note.dart';
import 'import_provenance_store.dart';

class ImportApplicationService {
  const ImportApplicationService(this.provenanceStore);

  final ImportProvenanceStore provenanceStore;

  Future<ImportSummary> apply({
    required String source,
    required String sourceInstance,
    required List<ImportDocument> documents,
    required List<Note> currentNotes,
    required Future<void> Function(Note note) save,
  }) async {
    if (documents.length > 10000) {
      throw const FormatException('Import oltre il limite di 10.000 elementi.');
    }
    final seenIdentity = <String>{};
    for (final document in documents) {
      document.identity.validate();
      if (document.identity.source != source ||
          document.identity.sourceInstance != sourceInstance) {
        throw const FormatException('Provenienza import incoerente.');
      }
      if (!seenIdentity.add(document.identity.key)) {
        throw const FormatException(
            'Elemento import duplicato nella sorgente.');
      }
    }

    final batchId = await provenanceStore.beginBatch(
      source: source,
      sourceInstance: sourceInstance,
    );
    final notesById = {
      for (final note in currentNotes) note.id: note,
    };
    var summary = const ImportSummary();
    var clock = DateTime.now().millisecondsSinceEpoch;

    for (final document in documents) {
      final record = await provenanceStore.find(document.identity);
      final local = record == null ? null : notesById[record.targetNoteId];
      final resolution = ImportProvenance.resolve(
        document: document,
        record: record,
        local: local,
      );
      final now = clock++;
      switch (resolution.decision) {
        case ImportDecision.create:
          final id = document.targetIdHint?.trim().isNotEmpty == true
              ? document.targetIdHint!.trim()
              : const Uuid().v4();
          if (notesById.containsKey(id)) {
            throw const FormatException(
              'Conflitto ID durante la creazione importata.',
            );
          }
          final created = Note(
            id: id,
            title: document.title,
            body: document.body,
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: NoteTags.normalize(document.tags),
            taskJson: document.taskJson,
          );
          await save(created);
          notesById[id] = created;
          final localFingerprint = ImportProvenance.fingerprintNote(created);
          await provenanceStore.upsert(
            ImportRecord(
              identity: document.identity,
              targetNoteId: id,
              externalFingerprint: document.externalFingerprint,
              localFingerprint: localFingerprint,
              lastBatchId: batchId,
              importedAt: record?.importedAt ?? now,
              lastSeenAt: now,
            ),
          );
          summary = summary.add(ImportDecision.create);
          break;

        case ImportDecision.update:
          final target = local!;
          final updated = Note(
            id: target.id,
            title: document.title,
            body: document.body,
            collectionId: target.collectionId,
            favorite: target.favorite,
            createdAt: target.createdAt,
            updatedAt: now,
            deletedAt: target.deletedAt,
            pinned: target.pinned,
            archived: target.archived,
            tags: NoteTags.normalize(document.tags),
            taskJson: document.taskJson,
          );
          await save(updated);
          notesById[target.id] = updated;
          await provenanceStore.upsert(
            ImportRecord(
              identity: document.identity,
              targetNoteId: target.id,
              externalFingerprint: document.externalFingerprint,
              localFingerprint: ImportProvenance.fingerprintNote(updated),
              lastBatchId: batchId,
              importedAt: record!.importedAt,
              lastSeenAt: now,
            ),
          );
          summary = summary.add(ImportDecision.update);
          break;

        case ImportDecision.unchanged:
          await provenanceStore.upsert(
            ImportRecord(
              identity: record!.identity,
              targetNoteId: record.targetNoteId,
              externalFingerprint: record.externalFingerprint,
              localFingerprint: record.localFingerprint,
              lastBatchId: batchId,
              importedAt: record.importedAt,
              lastSeenAt: now,
            ),
          );
          summary = summary.add(ImportDecision.unchanged);
          break;

        case ImportDecision.keepLocal:
          await provenanceStore.upsert(
            ImportRecord(
              identity: record!.identity,
              targetNoteId: record.targetNoteId,
              externalFingerprint: record.externalFingerprint,
              localFingerprint: record.localFingerprint,
              lastBatchId: batchId,
              importedAt: record.importedAt,
              lastSeenAt: now,
            ),
          );
          summary = summary.add(ImportDecision.keepLocal);
          break;

        case ImportDecision.conflict:
          final target = local!;
          final conflictId = const Uuid().v4();
          final conflict = Note(
            id: conflictId,
            title: document.title.trim().isEmpty
                ? 'Conflitto import'
                : '${document.title} · conflitto import',
            body: document.body,
            favorite: false,
            createdAt: now,
            updatedAt: now,
            pinned: false,
            archived: false,
            tags: NoteTags.normalize([
              ...document.tags,
              'import-conflict',
            ]),
            taskJson: document.taskJson,
          );
          await save(conflict);
          notesById[conflictId] = conflict;
          await provenanceStore.upsert(
            ImportRecord(
              identity: record!.identity,
              targetNoteId: target.id,
              externalFingerprint: document.externalFingerprint,
              localFingerprint: record.localFingerprint,
              lastBatchId: batchId,
              importedAt: record.importedAt,
              lastSeenAt: now,
            ),
          );
          summary = summary.add(ImportDecision.conflict);
          break;
      }
    }

    await provenanceStore.completeBatch(batchId, summary);
    return summary;
  }
}
