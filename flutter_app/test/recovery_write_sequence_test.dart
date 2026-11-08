import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/recovery_journal.dart';

void main() {
  test('exact eleven production phases are stable and explicit', () {
    expect(RecoveryWriteSequence.stages, [
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
    ]);
  });

  test('missing or extra store refuses to start any data writes', () async {
    var called = false;
    final incomplete = <String, Future<void> Function()>{
      for (final stage in RecoveryWriteSequence.stages.skip(1))
        stage: () async { called = true; },
    };
    await expectLater(
      RecoveryWriteSequence.run(incomplete),
      throwsFormatException,
    );
    expect(called, isFalse);
    incomplete['unknown-store'] = () async { called = true; };
    await expectLater(
      RecoveryWriteSequence.run(incomplete),
      throwsFormatException,
    );
    expect(called, isFalse);
  });

  test('each real named stage fault triggers journal rollback', () async {
    final dir = await Directory.systemTemp.createTemp('notes_stage_fault_');
    addTearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final original = Uint8List.fromList([4, 8, 12, 16]);
    for (final failedAt in RecoveryWriteSequence.stages) {
      final journal = RecoveryJournal(dir, syncDirectory: (_) async {});
      final data = <String, int>{
        for (final stage in RecoveryWriteSequence.stages) stage: 0,
      };
      final visited = <String>[];

      await expectLater(
        RecoveryTransaction.run(
          journal: journal,
          originalSnapshot: original,
          applyCandidate: () => RecoveryWriteSequence.run({
            for (final stage in RecoveryWriteSequence.stages)
              stage: () async {
                visited.add(stage);
                data[stage] = 1;
              },
          }, afterStage: (stage) async {
            if (stage == failedAt) throw StateError('fault at $stage');
          }),
          applyOriginal: (snapshot) async {
            expect(snapshot, orderedEquals(original));
            for (final stage in data.keys) {
              data[stage] = 0;
            }
          },
        ),
        throwsStateError,
      );
      expect(visited.last, failedAt);
      expect(visited.length,
          RecoveryWriteSequence.stages.indexOf(failedAt) + 1);
      expect(data.values, everyElement(0));
      expect(await journal.hasPending, isFalse);
    }
  });
}
