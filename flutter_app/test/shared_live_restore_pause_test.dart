import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/state/shared_live_sync_controller.dart';

void main() {
  test('restore refuses to begin while live sync is writing', () {
    final gate = SharedLiveRestorePauseGate();
    expect(gate.tryEnter(syncBusy: true), isFalse);
    expect(gate.isPaused, isFalse);
  });

  test('restore pause is exclusive and blocks overlapping acquisition', () {
    final gate = SharedLiveRestorePauseGate();
    expect(gate.tryEnter(syncBusy: false), isTrue);
    expect(gate.isPaused, isTrue);
    expect(gate.tryEnter(syncBusy: false), isFalse);
    gate.leave();
    expect(gate.isPaused, isFalse);
    expect(gate.tryEnter(syncBusy: false), isTrue);
  });

  test('release clears the paused state after an aborted restore', () {
    final gate = SharedLiveRestorePauseGate();
    expect(gate.tryEnter(syncBusy: false), isTrue);
    gate.leave();
    expect(gate.isPaused, isFalse);
    expect(gate.tryEnter(syncBusy: true), isFalse);
  });
}
