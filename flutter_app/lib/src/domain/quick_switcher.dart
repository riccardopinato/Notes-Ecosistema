import 'note.dart';

enum QuickSwitcherKind { note, task, collection, command }

class QuickSwitcherEntry {
  const QuickSwitcherEntry({
    required this.id,
    required this.label,
    required this.kind,
    this.subtitle,
  });

  final String id;
  final String label;
  final String? subtitle;
  final QuickSwitcherKind kind;
}

abstract final class QuickSwitcher {
  static List<QuickSwitcherEntry> search({
    required String query,
    required List<Note> notes,
    required List<NoteCollection> collections,
    int limit = 20,
  }) {
    final needle = _normalize(query);
    if (limit < 1 || limit > 100) {
      throw const FormatException('Limite Quick Switcher non valido.');
    }

    final entries = <QuickSwitcherEntry>[
      const QuickSwitcherEntry(
        id: 'today',
        label: 'Oggi',
        subtitle: 'Daily Work Briefing',
        kind: QuickSwitcherKind.command,
      ),
      const QuickSwitcherEntry(
        id: 'new-note',
        label: 'Nuova nota',
        kind: QuickSwitcherKind.command,
      ),
      const QuickSwitcherEntry(
        id: 'tasks',
        label: 'Attività',
        subtitle: 'Apri Planner Pro',
        kind: QuickSwitcherKind.command,
      ),
      const QuickSwitcherEntry(
        id: 'search',
        label: 'Cerca',
        subtitle: 'Ricerca completa',
        kind: QuickSwitcherKind.command,
      ),
      ...collections.map(
        (collection) => QuickSwitcherEntry(
          id: collection.id,
          label: collection.name,
          subtitle: 'Raccolta',
          kind: QuickSwitcherKind.collection,
        ),
      ),
      ...notes.where((note) => !note.isDeleted && !note.isVisual).map(
            (note) => QuickSwitcherEntry(
              id: note.id,
              label: note.title.trim().isEmpty
                  ? 'Senza titolo'
                  : note.title.trim(),
              subtitle: note.isTask ? 'Attività' : 'Nota',
              kind:
                  note.isTask ? QuickSwitcherKind.task : QuickSwitcherKind.note,
            ),
          ),
    ];

    int score(QuickSwitcherEntry entry) {
      if (needle.isEmpty)
        return entry.kind == QuickSwitcherKind.command ? 3 : 1;
      final label = _normalize(entry.label);
      final subtitle = _normalize(entry.subtitle ?? '');
      if (label == needle) return 100;
      if (label.startsWith(needle)) return 80;
      if (label.contains(needle)) return 60;
      if (subtitle.contains(needle)) return 30;
      return 0;
    }

    final ranked = entries
        .map((entry) => (entry: entry, score: score(entry)))
        .where((row) => row.score > 0)
        .toList()
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.entry.label.toLowerCase().compareTo(
              b.entry.label.toLowerCase(),
            );
      });

    return ranked.take(limit).map((row) => row.entry).toList(growable: false);
  }

  static String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
