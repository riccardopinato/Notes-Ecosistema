import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/project_workspace.dart';
import 'package:notes_ecosistema/src/domain/smart_inbox_project_action.dart';

void main() {
  const inserted = ProjectItemLink(
    projectId: 'private-project',
    noteId: 'private-source',
    position: 1,
    addedAt: 10,
    updatedAt: 10,
  );

  test('QA postcommit fence accepts unchanged source and exact receipt',
      () async {
    var undone = false;
    final result = await SmartInboxProjectCommitGuard.execute(
      write: () async => inserted,
      validateAfterWrite: (receipt) async =>
          SmartInboxProjectAction.canUndo(receipt, inserted),
      undoIfUnchanged: (_) async {
        undone = true;
        return true;
      },
    );
    expect(result, same(inserted));
    expect(undone, isFalse);
  });

  test('shared-role/account/source change during write triggers exact Undo',
      () async {
    var authorized = true;
    ProjectItemLink? undoneReceipt;
    await expectLater(
      SmartInboxProjectCommitGuard.execute(
        write: () async {
          authorized = false; // Simulated cross-store change during await.
          return inserted;
        },
        validateAfterWrite: (_) async => authorized,
        undoIfUnchanged: (receipt) async {
          undoneReceipt = receipt;
          return SmartInboxProjectAction.canUndo(receipt, inserted);
        },
      ),
      throwsA(isA<FormatException>().having(
        (e) => e.message,
        'message',
        'SMART_INBOX_RACE_ABORTED_AND_UNDONE',
      )),
    );
    expect(undoneReceipt, same(inserted));
  });

  test('unconfirmed conditional Undo never acknowledges a safe commit',
      () async {
    await expectLater(
      SmartInboxProjectCommitGuard.execute(
        write: () async => inserted,
        validateAfterWrite: (_) async => false,
        undoIfUnchanged: (_) async => false,
      ),
      throwsA(isA<FormatException>().having(
        (e) => e.message,
        'message',
        'SMART_INBOX_COMPENSATION_UNCONFIRMED',
      )),
    );
  });

  test('post-write revision read errors fail closed and attempt compensation',
      () async {
    var rolledBack = false;
    await expectLater(
      SmartInboxProjectCommitGuard.execute(
        write: () async => inserted,
        validateAfterWrite: (_) async {
          throw StateError('source DB disconnected');
        },
        undoIfUnchanged: (_) async {
          rolledBack = true;
          return true;
        },
      ),
      throwsFormatException,
    );
    expect(rolledBack, isTrue);
  });

  test('write error never invokes Undo on a link that was not inserted',
      () async {
    var compensated = false;
    await expectLater(
      SmartInboxProjectCommitGuard.execute(
        write: () async {
          throw const FormatException('ALREADY_LINKED');
        },
        validateAfterWrite: (_) async => true,
        undoIfUnchanged: (_) async {
          compensated = true;
          return true;
        },
      ),
      throwsFormatException,
    );
    expect(compensated, isFalse);
  });
}
