/// Pure visual navigation mapping: preserve the app's existing canonical
/// section indices. Search (section 5) stays reachable without a sixth tab.
/// Never changes routing, deep links, query state or tab storage.
abstract final class MobileNavigationUi5 {
  static const sections = <int>[0, 1, 3, 2, 4];

  static int sectionForDestination(int destinationIndex) =>
      sections[destinationIndex];

  static int destinationForSection(int sectionIndex) => switch (sectionIndex) {
        0 => 0,
        1 => 1,
        2 => 3,
        3 => 2,
        4 => 4,
        5 => 1, // Search renders NotesScreen in explicit searchMode.
        _ => throw RangeError.range(sectionIndex, 0, 5, 'sectionIndex'),
      };

  static const _titles = <String, List<String>>{
    'en': ['Home', 'Notes', 'Tasks', 'Diary', 'Spaces'],
    'it': ['Home', 'Note', 'Attività', 'Diario', 'Spazi'],
    'es': ['Inicio', 'Notas', 'Tareas', 'Diario', 'Espacios'],
    'fr': ['Accueil', 'Notes', 'Tâches', 'Journal', 'Espaces'],
    'de': ['Start', 'Notizen', 'Aufgaben', 'Tagebuch', 'Räume'],
    'pt': ['Início', 'Notas', 'Tarefas', 'Diário', 'Espaços'],
  };

  static String title(String locale, int index) {
    if (index < 0 || index >= sections.length) {
      throw RangeError.range(index, 0, sections.length - 1, 'index');
    }
    return (_titles[locale] ?? _titles['en']!)[index];
  }

  static bool get hasAllLocales =>
      _titles.length == 6 &&
      _titles.values.every((labels) =>
          labels.length == sections.length &&
          labels.every((label) => label.trim().isNotEmpty));
}
