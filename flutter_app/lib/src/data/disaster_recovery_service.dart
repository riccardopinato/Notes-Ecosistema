import 'dart:typed_data';

import '../domain/disaster_recovery.dart';
import '../domain/media_bundle.dart';
import 'derivative_store.dart';
import 'document_store.dart';
import 'knowledge_store.dart';
import 'legacy_notes_database.dart';
import 'project_store.dart';
import 'property_store.dart';
import 'study_store.dart';
import '../domain/attachments.dart';

typedef RecoveryStateExporter = Future<Map<String, Object?>> Function();
typedef RecoveryStateRestorer = Future<void> Function(
  Map<String, Object?> payload,
);

class DisasterRecoveryService {
  DisasterRecoveryService({
    required this.database,
    required this.propertyStore,
    required this.knowledgeStore,
    required this.derivativeStore,
    required this.projectStore,
    required this.studyStore,
    required this.documentStore,
    required this.exportSharedState,
    required this.restoreSharedState,
  });

  final LegacyNotesDatabase database;
  final PropertyStore propertyStore;
  final KnowledgeStore knowledgeStore;
  final DerivativeStore derivativeStore;
  final ProjectStore projectStore;
  final StudyStore studyStore;
  final DocumentStore documentStore;
  final RecoveryStateExporter exportSharedState;
  final RecoveryStateRestorer restoreSharedState;

  Future<Uint8List> exportArchive() async {
    final components = await _components();
    final snapshot = await database.snapshot();
    final store = await AttachmentStore.open();
    final assets = <String, Uint8List>{};
    for (final key in MediaBundle.referencedKeys(snapshot)) {
      assets[key] = await store.read(key);
    }
    return DisasterRecoveryArchive.encode(
      components: components,
      assets: assets,
    );
  }

  Future<void> restore(Uint8List bytes) async {
    final preview = DisasterRecoveryArchive.decode(bytes);
    const required = {
      'workspace',
      'properties',
      'knowledge',
      'derivatives',
      'projects',
      'shared',
      'study',
      'documents',
    };
    if (!preview.components.keys.toSet().containsAll(required)) {
      throw const FormatException(
        'Backup di emergenza incompleto.',
      );
    }

    // Capture a complete rollback point before the first destructive write.
    final rollback = await _components();
    final store = await AttachmentStore.open();
    for (final entry in preview.assets.entries) {
      await store.put(entry.key, entry.value);
    }

    try {
      await _restoreComponents(preview.components);
    } catch (_) {
      try {
        await _restoreComponents(rollback);
      } catch (_) {
        // Preserve the original failure. Every store uses a local transaction;
        // this compensating rollback is best-effort across separate databases.
      }
      rethrow;
    }

    final snapshot = await database.snapshot();
    await store.cleanup(MediaBundle.referencedKeys(snapshot));
  }

  Future<Map<String, Map<String, Object?>>> _components() async => {
        'workspace': await database.exportRecoveryState(),
        'properties': await propertyStore.exportBackup(),
        'knowledge': await knowledgeStore.exportBackup(),
        'derivatives': await derivativeStore.exportBackup(),
        'projects': await projectStore.exportBackup(),
        'shared': await exportSharedState(),
        'study': await studyStore.exportBackup(),
        'documents': await documentStore.exportBackup(),
      };

  Future<void> _restoreComponents(
    Map<String, Map<String, Object?>> components,
  ) async {
    await database.restoreRecoveryState(components['workspace']!);
    final noteIds =
        (await database.snapshot()).notes.map((note) => note.id).toSet();
    await propertyStore.restoreExact(
      components['properties']!,
      noteIds: noteIds,
    );
    await knowledgeStore.restoreExact(
      components['knowledge']!,
      noteIds: noteIds,
    );
    await derivativeStore.restoreExact(
      components['derivatives']!,
      noteIds: noteIds,
    );
    await projectStore.restoreExact(
      components['projects']!,
      noteIds: noteIds,
    );
    await studyStore.restoreExact(
      components['study']!,
      noteIds: noteIds,
    );
    await documentStore.restoreExact(
      components['documents']!,
      noteIds: noteIds,
    );
    await restoreSharedState(components['shared']!);
  }
}
