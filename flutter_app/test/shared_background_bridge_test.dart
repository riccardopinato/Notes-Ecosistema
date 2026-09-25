import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/platform/shared_background_bridge.dart';

void main() {
  test('background status exposes channel and restriction diagnostics', () {
    final status = SharedBackgroundStatus.fromMap({
      'enabledAt': 100,
      'lastCheckAt': 200,
      'lastSuccessAt': 190,
      'intervalMinutes': 15,
      'notificationsAllowed': true,
      'backgroundRestricted': false,
      'lastError': null,
    });

    expect(status.configured, isTrue);
    expect(status.healthy, isTrue);
    expect(status.notificationsAllowed, isTrue);
    expect(status.backgroundRestricted, isFalse);
    expect(status.intervalMinutes, 15);
  });

  test('background status uses safe defaults for missing native fields', () {
    final status = SharedBackgroundStatus.fromMap(const {});

    expect(status.configured, isFalse);
    expect(status.notificationsAllowed, isFalse);
    expect(status.backgroundRestricted, isFalse);
    expect(status.intervalMinutes, 15);
  });
}
