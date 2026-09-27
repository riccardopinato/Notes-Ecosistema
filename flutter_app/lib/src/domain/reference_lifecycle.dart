import 'knowledge.dart';
import 'note.dart';
import 'research.dart';

enum ReferenceLifecycleState {
  resolved,
  sourceMissing,
  deleted,
  stale,
  ambiguous,
}

extension ReferenceLifecycleStateCode on ReferenceLifecycleState {
  String get code => switch (this) {
        ReferenceLifecycleState.resolved => 'RESOLVED',
        ReferenceLifecycleState.sourceMissing => 'SOURCE_MISSING',
        ReferenceLifecycleState.deleted => 'DELETED',
        ReferenceLifecycleState.stale => 'STALE',
        ReferenceLifecycleState.ambiguous => 'AMBIGUOUS',
      };
}

enum ReferenceKind {
  internalLink,
  relation,
  syncedBlock,
  projectLink,
  sharedSpaceContent,
  visualReference,
}

class ReferenceResolution<T> {
  const ReferenceResolution({
    required this.kind,
    required this.referenceId,
    required this.state,
    this.value,
  });

  final ReferenceKind kind;
  final String referenceId;
  final ReferenceLifecycleState state;
  final T? value;

  bool get canOpen =>
      value != null &&
      (state == ReferenceLifecycleState.resolved ||
          state == ReferenceLifecycleState.stale);

  bool get isDangling =>
      state == ReferenceLifecycleState.sourceMissing ||
      state == ReferenceLifecycleState.deleted;
}

class RelationReferenceResolution {
  const RelationReferenceResolution({
    required this.relation,
    required this.otherNoteId,
    required this.target,
  });

  final NoteRelation relation;
  final String otherNoteId;
  final ReferenceResolution<Note> target;
}

abstract final class ReferenceLifecycle {
  static ReferenceResolution<Note> noteById({
    required String id,
    required Iterable<Note> notes,
    required ReferenceKind kind,
    int? expectedUpdatedAt,
  }) {
    final normalized = id.trim().toLowerCase();
    final matches = notes
        .where((note) => note.id.toLowerCase() == normalized)
        .toList(growable: false);

    if (matches.isEmpty) {
      return ReferenceResolution(
        kind: kind,
        referenceId: normalized,
        state: ReferenceLifecycleState.sourceMissing,
      );
    }
    if (matches.length > 1) {
      return ReferenceResolution(
        kind: kind,
        referenceId: normalized,
        state: ReferenceLifecycleState.ambiguous,
      );
    }

    final note = matches.single;
    if (note.isDeleted) {
      return ReferenceResolution(
        kind: kind,
        referenceId: normalized,
        state: ReferenceLifecycleState.deleted,
        value: note,
      );
    }
    if (expectedUpdatedAt != null && note.updatedAt > expectedUpdatedAt) {
      return ReferenceResolution(
        kind: kind,
        referenceId: normalized,
        state: ReferenceLifecycleState.stale,
        value: note,
      );
    }
    return ReferenceResolution(
      kind: kind,
      referenceId: normalized,
      state: ReferenceLifecycleState.resolved,
      value: note,
    );
  }

  static ReferenceResolution<Note> internalLink(
    NoteLink link,
    Iterable<Note> notes,
  ) =>
      noteById(
        id: link.id,
        notes: notes,
        kind: ReferenceKind.internalLink,
      );

  static RelationReferenceResolution relationOther({
    required NoteRelation relation,
    required String currentNoteId,
    required Iterable<Note> notes,
  }) {
    final current = currentNoteId.toLowerCase();
    final other = relation.sourceId.toLowerCase() == current
        ? relation.targetId
        : relation.targetId.toLowerCase() == current
            ? relation.sourceId
            : relation.targetId;
    return RelationReferenceResolution(
      relation: relation,
      otherNoteId: other,
      target: noteById(
        id: other,
        notes: notes,
        kind: ReferenceKind.relation,
      ),
    );
  }

  static ReferenceResolution<SyncedBlock> syncedBlock({
    required String id,
    required Map<String, SyncedBlock> blocks,
    int? expectedUpdatedAt,
  }) {
    final normalized = id.trim().toLowerCase();
    final matches = blocks.values
        .where((block) => block.id.toLowerCase() == normalized)
        .toList(growable: false);

    if (matches.isEmpty) {
      return ReferenceResolution(
        kind: ReferenceKind.syncedBlock,
        referenceId: normalized,
        state: ReferenceLifecycleState.sourceMissing,
      );
    }
    if (matches.length > 1) {
      return ReferenceResolution(
        kind: ReferenceKind.syncedBlock,
        referenceId: normalized,
        state: ReferenceLifecycleState.ambiguous,
      );
    }

    final block = matches.single;
    if (expectedUpdatedAt != null && block.updatedAt > expectedUpdatedAt) {
      return ReferenceResolution(
        kind: ReferenceKind.syncedBlock,
        referenceId: normalized,
        state: ReferenceLifecycleState.stale,
        value: block,
      );
    }
    return ReferenceResolution(
      kind: ReferenceKind.syncedBlock,
      referenceId: normalized,
      state: ReferenceLifecycleState.resolved,
      value: block,
    );
  }

  static String userLabel(ReferenceLifecycleState state) => switch (state) {
        ReferenceLifecycleState.resolved => 'Disponibile',
        ReferenceLifecycleState.sourceMissing => 'Sorgente non disponibile',
        ReferenceLifecycleState.deleted => 'Nel cestino',
        ReferenceLifecycleState.stale => 'Sorgente modificata',
        ReferenceLifecycleState.ambiguous => 'Riferimento ambiguo',
      };
}
