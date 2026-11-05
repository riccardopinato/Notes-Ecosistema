/// Deterministic, offline Italian/English draft parser. Never writes.
class NaturalLanguageTaskDraft {
  const NaturalLanguageTaskDraft({
    required this.title,
    required this.due,
    required this.priority,
    required this.unknownParts,
  });
  final String title;
  final String? due;
  final int priority;
  final List<String> unknownParts;
}

abstract final class NaturalLanguageTask {
  static final _priority = RegExp(
    r'(?:^|[,;\s])(?:priorit[aà]|priority)\s*[:=]?\s*(alta|media|bassa|high|medium|low)(?=$|[,;.!?\s])',
    caseSensitive: false,
    unicode: true,
  );
  static final _date = RegExp(
    r'(?:^|[,;\s])(?:entro|per(?:\s+il)?|by|due(?:\s+on)?|on)\s+'
    r'(oggi|domani|today|tomorrow|lunedi|lunedì|martedi|martedì|mercoledi|mercoledì|giovedi|giovedì|venerdi|venerdì|sabato|domenica|monday|tuesday|wednesday|thursday|friday|saturday|sunday|20\d{2}-\d{2}-\d{2})(?=$|[,;.!?\s])',
    caseSensitive: false,
    unicode: true,
  );
  static final _iso = RegExp(r'^20\d{2}-\d{2}-\d{2}$');

  static NaturalLanguageTaskDraft parse(String input,
      {required DateTime today}) {
    final raw = input.trim();
    if (raw.isEmpty || raw.length > 1000 || raw.contains('\u0000')) {
      throw const FormatException('Testo non valido (massimo 1000 caratteri).');
    }
    var title = raw;
    var priority = 0;
    String? due;
    final notes = <String>[];

    final priorities = _priority.allMatches(raw).toList(growable: false);
    if (priorities.length == 1) {
      priority = switch (priorities.single.group(1)!.toLowerCase()) {
        'alta' || 'high' => 3,
        'media' || 'medium' => 2,
        _ => 1,
      };
      title = title.replaceFirst(priorities.single.group(0)!, ' ');
    } else if (priorities.length > 1) {
      notes.add('Priorità multipla o ambigua');
    }

    final dates = _date.allMatches(title).toList(growable: false);
    if (dates.length == 1) {
      final parsed = _resolve(dates.single.group(1)!, today);
      if (parsed != null) {
        due = _dayKey(parsed);
        title = title.replaceFirst(dates.single.group(0)!, ' ');
      } else {
        notes.add('Data non valida o fuori intervallo');
      }
    } else if (dates.length > 1) {
      notes.add('Più scadenze indicate');
    }

    title = title.replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[,;.!?\s]+|[,;.!?\s]+$'), '')
        .trim();
    if (title.isEmpty || title.length > 200) {
      throw const FormatException(
          'Titolo non valido. Modifica il testo inserito.');
    }
    if (due == null && RegExp(r'\d{1,2}[/.-]\d{1,2}').hasMatch(raw)) {
      notes.add('Formato data ambiguo: verifica manualmente');
    }
    return NaturalLanguageTaskDraft(
      title: title,
      due: due,
      priority: priority,
      unknownParts: List.unmodifiable(notes),
    );
  }

  static NaturalLanguageTaskDraft validateEdited({
    required String title,
    required String due,
    required int priority,
  }) {
    final cleanTitle = title.trim();
    final cleanDue = due.trim();
    if (cleanTitle.isEmpty || cleanTitle.length > 200 ||
        cleanTitle.contains('\u0000') || priority < 0 || priority > 3) {
      throw const FormatException('Titolo o priorità non validi.');
    }
    if (cleanDue.isNotEmpty &&
        (!_iso.hasMatch(cleanDue) ||
            _parseIso(cleanDue) == null)) {
      throw const FormatException('Scadenza non valida: usa YYYY-MM-DD.');
    }
    return NaturalLanguageTaskDraft(
      title: cleanTitle,
      due: cleanDue.isEmpty ? null : cleanDue,
      priority: priority,
      unknownParts: const [],
    );
  }

  static DateTime? _resolve(String value, DateTime today) {
    final token = value.toLowerCase()
        .replaceAll('à', 'a').replaceAll('ì', 'i');
    final day = DateTime(today.year, today.month, today.day);
    if (_iso.hasMatch(token)) return _parseIso(token);
    if (token == 'today' || token == 'oggi') return day;
    if (token == 'tomorrow' || token == 'domani') {
      return DateTime(day.year, day.month, day.day + 1);
    }
    const days = {
      'lunedi': 1, 'monday': 1,
      'martedi': 2, 'tuesday': 2,
      'mercoledi': 3, 'wednesday': 3,
      'giovedi': 4, 'thursday': 4,
      'venerdi': 5, 'friday': 5,
      'sabato': 6, 'saturday': 6,
      'domenica': 7, 'sunday': 7,
    };
    final weekday = days[token];
    if (weekday == null) return null;
    return DateTime(day.year, day.month, day.day +
        ((weekday - day.weekday + 7) % 7));
  }

  static DateTime? _parseIso(String value) {
    if (!_iso.hasMatch(value)) return null;
    final parts = value.split('-').map(int.parse).toList(growable: false);
    final date = DateTime(parts[0], parts[1], parts[2]);
    if (date.year != parts[0] || date.month != parts[1] ||
        date.day != parts[2]) return null;
    return date;
  }

  static String _dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
