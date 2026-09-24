import 'note.dart';

class TemplateContent {
  const TemplateContent(this.title, this.body, this.tags);
  final String title;
  final String body;
  final List<String> tags;
}

class PageTemplate {
  const PageTemplate(this.key, this.name, this.title, this.body);
  final String key;
  final String name;
  final String title;
  final String body;
}

abstract final class PersonalTemplates {
  static const tag = 'modello';
  static final _variable = RegExp(r'\{\{(data|ora|giorno)\}\}');

  static bool eligible(Note note) =>
      !note.isDeleted &&
      !note.isTask &&
      !note.isVisual &&
      note.tags.contains(tag);

  static List<Note> catalog(List<Note> notes, [String query = '']) {
    final needle = query.trim().toLowerCase();
    final result = notes
        .where((note) =>
            eligible(note) &&
            (needle.isEmpty || note.title.toLowerCase().contains(needle)))
        .toList();
    result.sort((a, b) {
      final title = a.title.toLowerCase().compareTo(b.title.toLowerCase());
      return title != 0 ? title : a.id.compareTo(b.id);
    });
    return result;
  }

  static String expand(String text, DateTime now) {
    String two(int value) => value.toString().padLeft(2, '0');
    const weekdays = [
      'lunedì',
      'martedì',
      'mercoledì',
      'giovedì',
      'venerdì',
      'sabato',
      'domenica',
    ];
    return text.replaceAllMapped(_variable, (match) {
      switch (match.group(1)) {
        case 'data':
          return '${two(now.day)}/${two(now.month)}/${now.year}';
        case 'ora':
          return '${two(now.hour)}:${two(now.minute)}';
        default:
          return weekdays[now.weekday - 1];
      }
    });
  }

  static TemplateContent instantiate(
    String title,
    String body,
    List<String> tags,
    DateTime now, {
    bool reset = true,
  }) {
    var expanded = expand(body, now);
    if (reset) {
      expanded = expanded.replaceAllMapped(
        RegExp(r'(^|\n)(\s*- \[)[xX](\]\s*)'),
        (m) => '${m.group(1)}${m.group(2)} ${m.group(3)}',
      );
    }
    final heading = expand(title, now);
    if (heading.length > 8000 || expanded.length > 200000) {
      throw const FormatException('Il modello supera i limiti di una nota.');
    }
    final cleanTags = <String>{};
    for (final value in tags) {
      final tagValue = value.trim().toLowerCase();
      if (tagValue.isNotEmpty &&
          tagValue != tag &&
          !tagValue.startsWith('diario_')) {
        cleanTags.add(tagValue);
      }
    }
    final normalized = cleanTags.toList()..sort();
    return TemplateContent(heading, expanded, normalized);
  }

  static TemplateContent from(
    Note note,
    DateTime now, {
    bool reset = true,
  }) {
    if (!eligible(note)) {
      throw const FormatException(
        'Il modello non è più disponibile. Riapri la galleria.',
      );
    }
    return instantiate(note.title, note.body, note.tags, now, reset: reset);
  }

  static TemplateContent capture(String title, String body, List<String> tags) {
    if (title.trim().isEmpty && body.trim().isEmpty) {
      throw const FormatException(
        'Scrivi qualcosa prima di creare un modello.',
      );
    }
    if (title.length > 8000 || body.length > 200000) {
      throw const FormatException('La nota supera i limiti del modello.');
    }
    final next = <String>{...tags.map((e) => e.trim().toLowerCase()), tag}
        .where((e) => e.isNotEmpty)
        .toList()
      ..sort();
    if (next.length > 20) {
      throw const FormatException('Puoi usare fino a 20 tag.');
    }
    return TemplateContent(
      title.trim().isEmpty ? 'Modello personale' : title.trim(),
      body,
      next,
    );
  }
}

abstract final class PageTemplates {
  static const all = [
    PageTemplate('meeting', 'Riunione', 'Riunione',
        '# Obiettivo\\n\\n## Appunti\\n\\n## Decisioni\\n\\n## Prossime azioni\\n- [ ] '),
    PageTemplate('project', 'Progetto', 'Nuovo progetto',
        '# Risultato desiderato\\n\\n## Materiali e collegamenti\\n\\n## Prossimi passi\\n- [ ] \\n\\n## Decisioni\\n'),
    PageTemplate('study', 'Studio', 'Sessione di studio',
        '# Argomento\\n\\n## Concetti chiave\\n\\n## Domande\\n\\n## Riepilogo\\n'),
    PageTemplate('review', 'Revisione settimanale', 'Revisione settimanale',
        '# Cosa ho completato\\n\\n## Cosa ho imparato\\n\\n## Da riprendere\\n- [ ] \\n\\n## Priorità della prossima settimana\\n'),
  ];

  static PageTemplate daily(DateTime date) {
    final key =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return PageTemplate(
      'daily',
      'Diario di oggi',
      'Diario · $key',
      '# $key\\n\\n## Oggi conta\\n- [ ] \\n\\n## Appunti della giornata\\n\\n## Una cosa da ricordare\\n',
    );
  }
}
