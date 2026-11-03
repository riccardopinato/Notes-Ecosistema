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

String get plannerMatrixTitle => _t(
        it: 'Matrice Eisenhower',
        en: 'Eisenhower matrix',
        es: 'Matriz Eisenhower',
        fr: 'Matrice Eisenhower',
        de: 'Eisenhower-Matrix',
        pt: 'Matriz de Eisenhower',
      );

  String get plannerWeeklyTitle => _t(
        it: 'Riepilogo settimana',
        en: 'Weekly review',
        es: 'Resumen semanal',
        fr: 'Bilan hebdomadaire',
        de: 'Wochenrückblick',
        pt: 'Resumo semanal',
      );

  String get plannerMatrixHelp => _t(
        it: 'Sola lettura: urgente = scadenza entro due giorni; importante = priorità esplicita alta. Le attività senza dati sufficienti restano da classificare.',
        en: 'Read-only: urgent = due within two days; important = explicitly high priority. Tasks without enough data remain unclassified.',
        es: 'Solo lectura: urgente = vence en dos días; importante = prioridad alta explícita. Las tareas sin datos siguen sin clasificar.',
        fr: 'Lecture seule : urgent = échéance sous deux jours ; important = priorité élevée explicite. Sinon, la tâche reste à classer.',
        de: 'Nur Anzeige: dringend = Frist in zwei Tagen; wichtig = ausdrücklich hohe Priorität. Unvollständige Aufgaben bleiben ungeordnet.',
        pt: 'Somente leitura: urgente = prazo em dois dias; importante = prioridade alta explícita. Tarefas sem dados ficam sem classificação.',
      );

  String get plannerWeeklyHelp => _t(
        it: 'Settimana lunedì–domenica. Il completamento è contato solo quando è registrata una data effettiva. Nessuna attività viene modificata automaticamente.',
        en: 'Monday–Sunday. Completion is counted only with a recorded completion date. No task is changed automatically.',
        es: 'Semana de lunes a domingo. Solo se cuenta una finalización con fecha registrada. No se modifican tareas automáticamente.',
        fr: 'Semaine lundi–dimanche. Une tâche terminée n’est comptée que si sa date est enregistrée. Aucune modification automatique.',
        de: 'Montag–Sonntag. Erledigungen zählen nur mit dokumentiertem Datum. Keine automatische Änderung von Aufgaben.',
        pt: 'Semana de segunda a domingo. Conclusões só contam com data registrada. Nenhuma tarefa é alterada automaticamente.',
      );

  String get plannerUrgentImportant => _t(
        it: 'Urgente e importante',
        en: 'Urgent and important',
        es: 'Urgente e importante',
        fr: 'Urgent et important',
        de: 'Dringend und wichtig',
        pt: 'Urgente e importante',
      );

  String get plannerImportantNotUrgent => _t(
        it: 'Importante, non urgente',
        en: 'Important, not urgent',
        es: 'Importante, no urgente',
        fr: 'Important, non urgent',
        de: 'Wichtig, nicht dringend',
        pt: 'Importante, não urgente',
      );

  String get plannerUrgentNotImportant => _t(
        it: 'Urgente, non importante',
        en: 'Urgent, not important',
        es: 'Urgente, no importante',
        fr: 'Urgent, non important',
        de: 'Dringend, nicht wichtig',
        pt: 'Urgente, não importante',
      );

  String get plannerNeither => _t(
        it: 'Non urgente, non importante',
        en: 'Not urgent, not important',
        es: 'No urgente ni importante',
        fr: 'Ni urgent ni important',
        de: 'Weder dringend noch wichtig',
        pt: 'Nem urgente nem importante',
      );

  String get plannerUnclassified => _t(
        it: 'Da classificare',
        en: 'Needs review',
        es: 'Sin clasificar',
        fr: 'À classer',
        de: 'Noch einordnen',
        pt: 'Sem classificação',
      );

  String get plannerCompletedThisWeek => _t(
        it: 'Completate questa settimana',
        en: 'Completed this week',
        es: 'Completadas esta semana',
        fr: 'Terminées cette semaine',
        de: 'Diese Woche erledigt',
        pt: 'Concluídas nesta semana',
      );

  String get plannerDueThisWeek => _t(
        it: 'In scadenza questa settimana',
        en: 'Due this week',
        es: 'Vencen esta semana',
        fr: 'À échéance cette semaine',
        de: 'Diese Woche fällig',
        pt: 'Vencem nesta semana',
      );

  String get plannerOverdue => _t(
        it: 'Scadute prima della settimana',
        en: 'Overdue before this week',
        es: 'Vencidas antes de esta semana',
        fr: 'En retard avant cette semaine',
        de: 'Schon vorher überfällig',
        pt: 'Atrasadas antes desta semana',
      );

  String get plannerHighPriority => _t(
        it: 'Priorità alte aperte',
        en: 'Open high-priority tasks',
        es: 'Pendientes de prioridad alta',
        fr: 'Priorités élevées en cours',
        de: 'Offene Aufgaben mit hoher Priorität',
        pt: 'Tarefas abertas de alta prioridade',
      );

  String get plannerNoDue => _t(
        it: 'Senza scadenza',
        en: 'Without a due date',
        es: 'Sin vencimiento',
        fr: 'Sans échéance',
        de: 'Ohne Fälligkeitsdatum',
        pt: 'Sem prazo',
      );

  String get plannerGroupEmpty => _t(
        it: 'Nessuna attività in questa categoria.',
        en: 'No tasks in this category.',
        es: 'No hay tareas en esta categoría.',
        fr: 'Aucune tâche dans cette catégorie.',
        de: 'Keine Aufgaben in dieser Kategorie.',
        pt: 'Nenhuma tarefa nesta categoria.',
      );

  String plannerGroupTruncated(int count) => _t(
        it: 'Mostrate 15 di $count attività.',
        en: 'Showing 15 of $count tasks.',
        es: 'Se muestran 15 de $count tareas.',
        fr: '15 tâches affichées sur $count.',
        de: '15 von $count Aufgaben angezeigt.',
        pt: 'Mostrando 15 de $count tarefas.',
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
