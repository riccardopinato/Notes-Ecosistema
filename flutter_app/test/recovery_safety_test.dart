import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/recovery_safety.dart';

void main() {
  test('exact externally read-back backup passes the pre-restore gate', () {
    final generated = Uint8List.fromList([1, 8, 3, 42, 255]);
    final readBack = Uint8List.fromList(generated);
    expect(
      () => RecoverySafety.requireVerifiedExternalCopy(
        generated: generated,
        readBack: readBack,
      ),
      returnsNormally,
    );
  });

  test('cancelled or unreadable external copy blocks restore', () {
    expect(
      () => RecoverySafety.requireVerifiedExternalCopy(
        generated: Uint8List.fromList([1, 2, 3]),
        readBack: null,
      ),
      throwsFormatException,
    );
  });

  test('truncated external copy blocks restore', () {
    expect(
      () => RecoverySafety.requireVerifiedExternalCopy(
        generated: Uint8List.fromList([1, 2, 3]),
        readBack: Uint8List.fromList([1, 2]),
      ),
      throwsFormatException,
    );
  });

  test('equal-size tampering blocks restore without first-byte shortcuts', () {
    final generated = Uint8List.fromList(
      List<int>.generate(1024, (i) => i % 256),
    );
    final tampered = Uint8List.fromList(generated);
    tampered[1023] ^= 1;
    expect(
      () => RecoverySafety.requireVerifiedExternalCopy(
        generated: generated,
        readBack: tampered,
      ),
      throwsFormatException,
    );
  });
}
