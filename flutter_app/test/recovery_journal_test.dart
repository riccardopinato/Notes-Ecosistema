import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/recovery_journal.dart';

void main() {
  // Production requires native directory fsync. Unit fixtures provide an
  // explicit durability adapter; never silently skip it in the app.
  RecoveryJournal testJournal(Directory directory) => RecoveryJournal(
        directory,
        syncDirectory: (_) async {},
      );

  late Directory temp;
  late RecoveryJournal journal;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('notes_restore_');
    journal = testJournal(temp);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('durable snapshot survives reopening and marker is explicit', () async {
    final before = Uint8List.fromList([10, 20, 30, 40]);
    await journal.begin(before);
    expect(await journal.hasPending, isTrue);
    final reopened = testJournal(temp);
    expect(await reopened.readPending(), orderedEquals(before));
    await reopened.complete();
    expect(await reopened.hasPending, isFalse);
    expect(await reopened.readPending(), isNull);
  });

  test('cannot overwrite a pending pre-restore snapshot', () async {
    final before = Uint8List.fromList([1, 2, 3]);
    await journal.begin(before);
    await expectLater(
      journal.begin(Uint8List.fromList([9, 9, 9])),
      throwsFormatException,
    );
    expect(await journal.readPending(), orderedEquals(before));
  });

  test('corrupt or absent pre-restore bytes fail closed', () async {
    await journal.begin(Uint8List.fromList([1, 2, 3]));
    await File('${temp.path}/pre_restore.zip').writeAsBytes([1, 2, 4]);
    await expectLater(journal.readPending(), throwsFormatException);
    expect(await journal.hasPending, isTrue);
    await File('${temp.path}/pre_restore.zip').delete();
    await expectLater(journal.readPending(), throwsFormatException);
    expect(await journal.hasPending, isTrue);
  });

  test('invalid pending metadata blocks restore without deletion', () async {
    await journal.begin(Uint8List.fromList([1, 2, 3]));
    await File('${temp.path}/pending.json').writeAsString('truncated');
    await expectLater(journal.readPending(), throwsFormatException);
    expect(await journal.hasPending, isTrue);
  });

  test('fault injection rolls back every interrupted store phase', () async {
    final before = Uint8List.fromList([3, 4, 5]);
    for (var failedStep = 0; failedStep < 11; failedStep++) {
      final state = List<int>.filled(11, 0);
      await expectLater(
        RecoveryTransaction.run(
          journal: journal,
          originalSnapshot: before,
          applyCandidate: () async {
            for (var step = 0; step < 11; step++) {
              state[step] = 1;
              if (step == failedStep) throw StateError('injected $step');
            }
          },
          applyOriginal: (snapshot) async {
            expect(snapshot, orderedEquals(before));
            for (var step = 0; step < 11; step++) {
              state[step] = 0;
            }
          },
        ),
        throwsStateError,
      );
      expect(state, everyElement(0));
      expect(await journal.hasPending, isFalse);
    }
  });

  test('failed rollback stays pending and can resume after restart', () async {
    final before = Uint8List.fromList([7, 8, 9]);
    var firstAttempt = true;
    final data = <int>[1, 2, 3];
    await expectLater(
      RecoveryTransaction.run(
        journal: journal,
        originalSnapshot: before,
        applyCandidate: () async {
          data[0] = 99;
          throw StateError('crash');
        },
        applyOriginal: (_) async {
          if (firstAttempt) throw StateError('no storage');
          data[0] = 1;
        },
      ),
      throwsStateError,
    );
    expect(await journal.hasPending, isTrue);
    firstAttempt = false;
    expect(
      await RecoveryTransaction.recoverPending(
        journal: testJournal(temp),
        applyOriginal: (snapshot) async {
          expect(snapshot, orderedEquals(before));
          data[0] = 1;
        },
      ),
      isTrue,
    );
    expect(data, [1, 2, 3]);
    expect(await journal.hasPending, isFalse);
  });

  test('completed transaction does not roll back on restart', () async {
    var value = 0;
    await RecoveryTransaction.run(
      journal: journal,
      originalSnapshot: Uint8List.fromList([0]),
      applyCandidate: () async => value = 1,
      applyOriginal: (_) async => value = 0,
    );
    expect(value, 1);
    expect(
      await RecoveryTransaction.recoverPending(
        journal: testJournal(temp),
        applyOriginal: (_) async => value = -1,
      ),
      isFalse,
    );
    expect(value, 1);
  });
  test('startup recovery replays a pending crash even without prior exception',
      () async {
    final before = Uint8List.fromList([11, 22, 33]);
    await journal.begin(before);
    // Simulate process death after one of several store writes.
    final active = <int>[99, 2, 3];
    final reopened = testJournal(temp);
    expect(
      await RecoveryTransaction.recoverPending(
        journal: reopened,
        applyOriginal: (snapshot) async {
          expect(snapshot, orderedEquals(before));
          active[0] = 1;
        },
      ),
      isTrue,
    );
    expect(active, [1, 2, 3]);
    expect(await reopened.hasPending, isFalse);
  });
  test('a failed directory sync refuses to authorize any store writes',
      () async {
    final unsafe = RecoveryJournal(
      temp,
      syncDirectory: (_) async {
        throw FileSystemException('Directory fsync failure');
      },
    );
    await expectLater(
      unsafe.begin(Uint8List.fromList([1, 2, 3])),
      throwsA(isA<FileSystemException>()),
    );
    expect(await unsafe.hasPending, isFalse);
  });

  test('failed marker durability leaves a detectable pending transaction',
      () async {
    var barriers = 0;
    final unsafe = RecoveryJournal(
      temp,
      syncDirectory: (_) async {
        barriers++;
        if (barriers == 3) {
          throw FileSystemException('Marker fsync failure');
        }
      },
    );
    final before = Uint8List.fromList([4, 5, 6]);
    await expectLater(
        unsafe.begin(before), throwsA(isA<FileSystemException>()));
    expect(await unsafe.hasPending, isTrue);
    final reopened = testJournal(temp);
    expect(await reopened.readPending(), orderedEquals(before));
    await reopened.complete();
  });

  test('uncertain completion barrier blocks reuse without rolling back data',
      () async {
    var barriers = 0;
    var allowRetry = false;
    final flaky = RecoveryJournal(
      temp,
      syncDirectory: (_) async {
        barriers++;
        if (barriers >= 4 && !allowRetry) {
          throw FileSystemException('Completed marker fsync failed');
        }
      },
    );
    await flaky.begin(Uint8List.fromList([8, 8, 8]));
    await expectLater(flaky.complete(), throwsA(isA<FileSystemException>()));

    // A committed marker exists but cannot be trusted for new local edits
    // until the failed directory barrier has been retried.
    expect(await flaky.hasPending, isFalse);
    await expectLater(flaky.hasUnsettled, throwsA(isA<FileSystemException>()));
    allowRetry = true;
    var rollbackCalled = false;
    expect(
      await RecoveryTransaction.recoverPending(
        journal: flaky,
        applyOriginal: (_) async {
          rollbackCalled = true;
        },
      ),
      isFalse,
    );
    expect(rollbackCalled, isFalse);
    expect(await flaky.hasUnsettled, isFalse);
    expect(await flaky.readPending(), isNull);
  });

  test('fresh process must re-fsync completed marker before opening UI',
      () async {
    await journal.begin(Uint8List.fromList([4, 4, 4]));
    await journal.complete();
    var attempts = 0;
    final reopened = RecoveryJournal(
      temp,
      syncDirectory: (_) async {
        attempts++;
        if (attempts == 1) {
          throw FileSystemException('New process cannot verify barrier');
        }
      },
    );

    await expectLater(
        reopened.hasUnsettled, throwsA(isA<FileSystemException>()));
    expect(await reopened.hasPending, isFalse);
    expect(await reopened.hasUnsettled, isFalse);
    expect(attempts, 2);
  });
}
