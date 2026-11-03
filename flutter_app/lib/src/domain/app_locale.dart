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

String get noteChecklistAction => _t(
        it: 'Da nota a checklist',
        en: 'Note to checklist',
        es: 'De nota a lista',
        fr: 'Note en checklist',
        de: 'Notiz als Checkliste',
        pt: 'Nota para checklist',
      );

  String get noteChecklistTitle => _t(
        it: 'Crea checklist dalla nota',
        en: 'Create checklist from note',
        es: 'Crear lista desde la nota',
        fr: 'Créer une checklist depuis la note',
        de: 'Checkliste aus Notiz erstellen',
        pt: 'Criar checklist da nota',
      );

  String get noteChecklistHelp => _t(
        it: 'Controlla le voci. Verrà creata una sola attività nel Planner con le sotto-attività selezionate. La nota originale rimarrà invariata.',
        en: 'Review the items. One Planner task will be created with the selected subtasks. The original note will not change.',
        es: 'Revisa las opciones. Se creará una tarea con las subtareas elegidas. La nota original no cambiará.',
        fr: 'Vérifiez les éléments. Une tâche sera créée avec les sous-tâches choisies. La note originale restera inchangée.',
        de: 'Prüfe die Einträge. Eine Aufgabe mit den gewählten Teilaufgaben wird erstellt. Die ursprüngliche Notiz bleibt unverändert.',
        pt: 'Revise os itens. Uma tarefa será criada com as subtarefas selecionadas. A nota original não será alterada.',
      );

  String get noteChecklistCreate => _t(
        it: 'Crea attività',
        en: 'Create task',
        es: 'Crear tarea',
        fr: 'Créer une tâche',
        de: 'Aufgabe erstellen',
        pt: 'Criar tarefa',
      );

  String get noteChecklistCancel => _t(
        it: 'Annulla',
        en: 'Cancel',
        es: 'Cancelar',
        fr: 'Annuler',
        de: 'Abbrechen',
        pt: 'Cancelar',
      );

  String get noteChecklistSaveFirst => _t(
        it: 'Salva prima la nota per creare la checklist.',
        en: 'Save the note before creating a checklist.',
        es: 'Guarda la nota antes de crear una lista.',
        fr: 'Enregistrez la note avant de créer la checklist.',
        de: 'Speichere zuerst die Notiz, um eine Checkliste zu erstellen.',
        pt: 'Salve a nota antes de criar a checklist.',
      );

  String get noteChecklistNoItems => _t(
        it: 'Nessuna riga elenco da trasformare in checklist.',
        en: 'No list items to convert into a checklist.',
        es: 'No hay elementos de lista para convertir.',
        fr: 'Aucun élément de liste à convertir.',
        de: 'Keine Listeneinträge zum Umwandeln vorhanden.',
        pt: 'Nenhum item de lista para converter.',
      );

  String get noteChecklistCreated => _t(
        it: 'Checklist creata nel Planner. Nota invariata.',
        en: 'Checklist created in Planner. Note unchanged.',
        es: 'Lista creada en Planner. Nota sin cambios.',
        fr: 'Checklist créée dans Planner. Note inchangée.',
        de: 'Checkliste im Planner erstellt. Notiz unverändert.',
        pt: 'Checklist criada no Planner. Nota inalterada.',
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
