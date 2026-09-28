import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/app_locale.dart';

void main() {
  test('app locale follows supported override and system fallback contract', () {
    expect(AppLocale.normalizePreference(null), isNull);
    expect(AppLocale.normalizePreference('system'), isNull);
    expect(AppLocale.normalizePreference('IT'), 'it');
    expect(AppLocale.normalizePreference('de'), 'de');
    expect(AppLocale.normalizePreference('ja'), isNull);

    expect(AppLocale.localeForPreference('fr'), const Locale('fr'));
    expect(AppLocale.localeForPreference('system'), isNull);
    expect(AppLocale.effectiveCode(const Locale('pt', 'BR')), 'pt');
    expect(AppLocale.effectiveCode(const Locale('ja')), 'en');
  });

  test('supported locale contract contains the six required languages', () {
    expect(
      AppLocale.supportedLocales.map((locale) => locale.languageCode).toList(),
      ['en', 'it', 'es', 'fr', 'de', 'pt'],
    );
  });
}
