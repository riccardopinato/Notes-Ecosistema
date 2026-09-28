import 'package:flutter/material.dart';

abstract final class AppLocale {
  static const preferenceKey = 'app_locale_v1';

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('it'),
    Locale('es'),
    Locale('fr'),
    Locale('de'),
    Locale('pt'),
  ];

  static const supportedCodes = <String>{
    'en',
    'it',
    'es',
    'fr',
    'de',
    'pt',
  };

  static String? normalizePreference(String? value) {
    final code = value?.trim().toLowerCase();
    if (code == null || code.isEmpty || code == 'system') return null;
    return supportedCodes.contains(code) ? code : null;
  }

  static Locale? localeForPreference(String? value) {
    final code = normalizePreference(value);
    return code == null ? null : Locale(code);
  }

  static String effectiveCode(Locale locale) =>
      supportedCodes.contains(locale.languageCode) ? locale.languageCode : 'en';

  static String label(String? value) => switch (normalizePreference(value)) {
        'it' => 'Italiano',
        'en' => 'English',
        'es' => 'Español',
        'fr' => 'Français',
        'de' => 'Deutsch',
        'pt' => 'Português',
        _ => 'Sistema',
      };
}

class AppStrings {
  const AppStrings(this.code);

  final String code;

  factory AppStrings.of(BuildContext context) =>
      AppStrings(AppLocale.effectiveCode(Localizations.localeOf(context)));

  String get automations => _t(
        it: 'Automazioni',
        en: 'Automations',
        es: 'Automatizaciones',
        fr: 'Automatisations',
        de: 'Automationen',
        pt: 'Automações',
      );

  String get automationsSubtitle => _t(
        it: 'Regole locali evento → azione, senza AI.',
        en: 'Local event → action rules, without AI.',
        es: 'Reglas locales evento → acción, sin IA.',
        fr: 'Règles locales événement → action, sans IA.',
        de: 'Lokale Ereignis→Aktion-Regeln, ohne KI.',
        pt: 'Regras locais evento → ação, sem IA.',
      );

  String get newRule => _t(
        it: 'Nuova regola',
        en: 'New rule',
        es: 'Nueva regla',
        fr: 'Nouvelle règle',
        de: 'Neue Regel',
        pt: 'Nova regra',
      );

  String get recentRuns => _t(
        it: 'Esecuzioni recenti',
        en: 'Recent runs',
        es: 'Ejecuciones recientes',
        fr: 'Exécutions récentes',
        de: 'Letzte Ausführungen',
        pt: 'Execuções recentes',
      );

  String get noRules => _t(
        it: 'Nessuna automazione. Crea una regola semplice e reversibile.',
        en: 'No automations. Create a simple, reversible rule.',
        es: 'Sin automatizaciones. Crea una regla simple y reversible.',
        fr: 'Aucune automatisation. Créez une règle simple et réversible.',
        de: 'Keine Automationen. Erstelle eine einfache, reversible Regel.',
        pt: 'Sem automações. Crie uma regra simples e reversível.',
      );

  String get language => _t(
        it: 'Lingua app',
        en: 'App language',
        es: 'Idioma de la app',
        fr: 'Langue de l’app',
        de: 'App-Sprache',
        pt: 'Idioma do app',
      );

  String get profile => _t(
        it: 'Profilo',
        en: 'Profile',
        es: 'Perfil',
        fr: 'Profil',
        de: 'Profil',
        pt: 'Perfil',
      );

  String get systemLanguage => _t(
        it: 'Sistema',
        en: 'System',
        es: 'Sistema',
        fr: 'Système',
        de: 'System',
        pt: 'Sistema',
      );

  String _t({
    required String it,
    required String en,
    required String es,
    required String fr,
    required String de,
    required String pt,
  }) =>
      switch (code) {
        'it' => it,
        'es' => es,
        'fr' => fr,
        'de' => de,
        'pt' => pt,
        _ => en,
      };
}
