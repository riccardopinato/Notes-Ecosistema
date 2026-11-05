import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/privacy_copy.dart';

void main() {
  test('email and validated Italian IBAN are proposed, not auto-masked', () {
    const text = 'Contatto abc@example.com e IBAN IT60X0542811101000000123456.';
    final matches = PrivacyCopy.scan(text);
    expect(matches.map((x) => x.kind),
        [PrivacyMatchKind.email, PrivacyMatchKind.iban]);
    expect(PrivacyCopy.redact(text, [0]), contains('IT60X0542811101000000123456'));
    final redacted = PrivacyCopy.redact(text, [0, 1]);
    expect(redacted, isNot(contains('abc@example.com')));
    expect(redacted, isNot(contains('IT60X0542811101000000123456')));
    expect(text, contains('abc@example.com'));
  });

  test('invalid IBAN checksum is not a claimed detection', () {
    expect(PrivacyCopy.scan('IT00X0542811101000000123456'), isEmpty);
  });

  test('unselected identifiers survive; no findings means no mutation', () {
    const text = 'a@b.com c@d.com';
    expect(PrivacyCopy.redact(text, []), text);
    final masked = PrivacyCopy.redact(text, [1]);
    expect(masked, contains('a@b.com'));
    expect(masked, isNot(contains('c@d.com')));
  });

  test('oversized sources and forged indices fail closed', () {
    expect(() => PrivacyCopy.scan('x' * 50001), throwsFormatException);
    expect(() => PrivacyCopy.redact('a@b.com', [-1]), throwsFormatException);
    expect(() => PrivacyCopy.redact('a@b.com', [3]), throwsFormatException);
  });
}
