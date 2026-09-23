class NoteLink {
  const NoteLink(this.id, this.label, this.start, this.end);
  final String id;
  final String label;
  final int start;
  final int end;
}

class NoteHeading {
  const NoteHeading(this.title, this.level, this.offset);
  final String title;
  final int level;
  final int offset;
}

class MarkdownSelectionEdit {
  const MarkdownSelectionEdit(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;
}

abstract final class Knowledge {
  static const _uuid =
      r'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}';

  static String? targetId(String uri) {
    final match = RegExp('^notes://note/($_uuid)\\$').firstMatch(uri);
    return match?.group(1)?.toLowerCase();
  }

  static String url(String id) {
    if (!RegExp('^$_uuid\\$').hasMatch(id)) {
      throw const FormatException('Identificatore della nota non valido.');
    }
    return 'notes://note/${id.toLowerCase()}';
  }

  static MarkdownSelectionEdit insert(
    String text,
    int start,
    int end,
    String id,
    String label,
  ) {
    final a = (start < end ? start : end).clamp(0, text.length).toInt();
    final b = (start < end ? end : start).clamp(a, text.length).toInt();
    var safe = label.length > 300 ? label.substring(0, 300) : label;
    safe = safe
        .replaceAll('\\\\', '\\\\\\\\')
        .replaceAll('[', '\\\\[')
        .replaceAll(']', '\\\\]')
        .replaceAll('\\n', ' ')
        .replaceAll('\\r', ' ')
        .trim();
    if (safe.isEmpty) safe = 'Nota';
    final value = '[$safe](${url(id)})';
    final next = text.replaceRange(a, b, value);
    return MarkdownSelectionEdit(next, a + value.length, a + value.length);
  }

  static List<NoteLink> links(String text) {
    final regex = RegExp(
      '(?<!\\\\\\\\!)\\\\\\\\[((?:\\\\\\\\\\\\\\\\.|[^\\\\\\\\]\\\\\\\\r\\\\\\\\n])*)\\\\\\\\]\\\\\\\\(notes://note/($_uuid)\\\\\\\\)',
    );
    return regex.allMatches(text).map((match) {
      final label = (match.group(1) ?? '').replaceAllMapped(
        RegExp(r'\\\\(.)'),
        (m) => m.group(1) ?? '',
      );
      return NoteLink(
        match.group(2)!.toLowerCase(),
        label,
        match.start,
        match.end,
      );
    }).toList(growable: false);
  }

  static String remap(String text, Map<String, String> ids) {
    var result = text;
    for (final ref in links(text).reversed) {
      final replacement = ids[ref.id];
      if (replacement == null) continue;
      final old = result.substring(ref.start, ref.end);
      final marker = old.lastIndexOf('notes://note/');
      if (marker < 0) continue;
      result = result.replaceRange(
        ref.start + marker,
        ref.end - 1,
        url(replacement),
      );
    }
    return result;
  }

  static List<NoteHeading> headings(String text) {
    final result = <NoteHeading>[];
    var offset = 0;
    var fenceChar = '';
    var fenceLength = 0;
    final fenceRegex = RegExp(r'^ {0,3}((?:\\x60){3,}|~{3,})(.*)\\$');
    for (final raw in text.split('\\n')) {
      final line = raw.replaceFirst(RegExp(r'\\r\\$'), '');
      final fence = fenceRegex.firstMatch(line);
      var hidden =
          fenceChar.isNotEmpty || line.startsWith('    ') || line.startsWith('\\t');
      if (fence != null) {
        final token = fence.group(1)!;
        final tail = fence.group(2)!;
        if (fenceChar.isEmpty &&
            !(token.codeUnitAt(0) == 0x60 && tail.contains(String.fromCharCode(0x60)))) {
          fenceChar = token[0];
          fenceLength = token.length;
          hidden = true;
        } else if (fenceChar == token[0] &&
            token.length >= fenceLength &&
            tail.trim().isEmpty) {
          fenceChar = '';
          fenceLength = 0;
          hidden = true;
        }
      }
      if (!hidden) {
        final match =
            RegExp(r'^ {0,3}(#{1,6})(?:[ \\t]+|\\$)(.*)\\$').firstMatch(line);
        if (match != null) {
          final title = (match.group(2) ?? '')
              .replaceFirst(RegExp(r'[ \\t]+#+[ \\t]*\\$'), '')
              .trim();
          result.add(NoteHeading(title, match.group(1)!.length, offset));
        }
      }
      offset += raw.length + 1;
    }
    return result;
  }
}

abstract final class LiteralSearch {
  static List<({int start, int end})> ranges(
    String text,
    String query, {
    bool ignoreCase = true,
  }) {
    if (query.isEmpty) return const [];
    final source = ignoreCase ? text.toLowerCase() : text;
    final needle = ignoreCase ? query.toLowerCase() : query;
    final result = <({int start, int end})>[];
    var from = 0;
    while (from <= source.length - needle.length) {
      final index = source.indexOf(needle, from);
      if (index < 0) break;
      result.add((start: index, end: index + needle.length));
      from = index + needle.length;
    }
    return result;
  }

  static MarkdownSelectionEdit replaceAll(
    String text,
    String query,
    String replacement, {
    bool ignoreCase = true,
  }) {
    final matches = ranges(text, query, ignoreCase: ignoreCase);
    final length =
        text.length + matches.length * (replacement.length - query.length);
    if (length > 200000) {
      throw const FormatException(
        'Il risultato supera 200.000 caratteri. Riduci la sostituzione.',
      );
    }
    final out = StringBuffer();
    var last = 0;
    for (final range in matches) {
      out
        ..write(text.substring(last, range.start))
        ..write(replacement);
      last = range.end;
    }
    out.write(text.substring(last));
    return MarkdownSelectionEdit(out.toString(), 0, 0);
  }
}
