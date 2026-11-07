import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/widgets/home_ui5_strings.dart';

void main() {
  test('UI5 labels cover all six supported locales with the same keys', () {
    final english = HomeUi5Strings.translations['en']!.keys.toSet();
    for (final code in ['en', 'it', 'es', 'fr', 'de', 'pt']) {
      final labels = HomeUi5Strings.translations[code]!;
      expect(labels.keys.toSet(), english, reason: code);
      expect(labels.values.every((value) => value.trim().isNotEmpty), isTrue);
    }
    expect(HomeUi5Strings.label('xx', 'newNote'), 'New note');
  });
}
