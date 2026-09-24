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

  static bool _validId(String value) {
    final match = RegExp(_uuid).firstMatch(value);
    return match != null && match.start == 0 && match.end == value.length;
  }

  static String? targetId(String uri) {
    const prefix = 'notes://note/';
    if (!uri.startsWith(prefix)) return null;
    final candidate = uri.substring(prefix.length);
    return _validId(candidate) ? candidate.toLowerCase() : null;
  }

  static String url(String id) {
    if (!_validId(id)) {
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
        .replaceAll('\\', '\\\\')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll('\n', ' ')
        .replaceAll('\r', ' ')
        .trim();
    if (safe.isEmpty) safe = 'Nota';
    final value = '[$safe](${url(id)})';
    final next = text.replaceRange(a, b, value);
    return MarkdownSelectionEdit(next, a + value.length, a + value.length);
  }

  static List<NoteLink> links(String text) {
    final regex = RegExp(
      r'(?<!!)\[((?:\\.|[^\]\r\n])*)\]\(notes://note/(' + _uuid + r')\)',
    );
    final visible = _visible(text);
    return regex
        .allMatches(text)
        .where(
          (match) =>
              !_escaped(text, match.start) &&
              match.start < visible.length &&
              List<int>.generate(
                match.end - match.start,
                (index) => match.start + index,
              ).every((index) => visible[index]),
        )
        .map(
          (match) => NoteLink(
            match.group(2)!.toLowerCase(),
            (match.group(1) ?? '').replaceAllMapped(
              RegExp(r'\\(.)'),
              (m) => m.group(1) ?? '',
            ),
            match.start,
            match.end,
          ),
        )
        .toList(growable: false);
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
    final mask = _visible(text);
    final result = <NoteHeading>[];
    var offset = 0;
    for (final raw in text.split('\n')) {
      final line = raw.replaceFirst(RegExp(r'\r'), '');
      if (offset < mask.length && mask[offset]) {
        final match =
            RegExp(r'^ {0,3}(#{1,6})(?:[ \t]+|\z)(.*)').firstMatch(line);
        if (match != null) {
          final title = (match.group(2) ?? '')
              .replaceFirst(RegExp(r'[ \t]+#+[ \t]*'), '')
              .trim();
          result.add(NoteHeading(title, match.group(1)!.length, offset));
        }
      }
      offset += raw.length + 1;
    }
    return result;
  }

  static List<bool> _visible(String text) {
    final visible = List<bool>.filled(text.length, true);
    var fenceChar = '';
    var fenceSize = 0;
    var offset = 0;
    final fence = RegExp(r'^ {0,3}((?:\x60){3,}|~{3,})(.*)');
    for (final raw in text.split('\n')) {
      final line = raw.replaceFirst(RegExp(r'\r'), '');
      final match = fence.firstMatch(line);
      var hidden = fenceChar.isNotEmpty ||
          line.startsWith('    ') ||
          line.startsWith('\t');

      if (match != null) {
        final token = match.group(1)!;
        final tail = match.group(2) ?? '';
        final tokenChar = token[0];
        if (fenceChar.isEmpty &&
            !(tokenChar.codeUnitAt(0) == 0x60 &&
                tail.contains(String.fromCharCode(0x60)))) {
          fenceChar = tokenChar;
          fenceSize = token.length;
          hidden = true;
        } else if (fenceChar == tokenChar &&
            token.length >= fenceSize &&
            tail.trim().isEmpty) {
          fenceChar = '';
          fenceSize = 0;
          hidden = true;
        }
      }

      if (hidden) {
        final end = (offset + raw.length).clamp(0, text.length).toInt();
        for (var i = offset; i < end; i++) {
          visible[i] = false;
        }
      }
      offset += raw.length + 1;
    }

    final tickRegex = RegExp(r'(?:\x60)+');
    final ticks = tickRegex
        .allMatches(text)
        .where((match) => match.start < visible.length && visible[match.start])
        .toList();
    for (var i = 0; i < ticks.length; i++) {
      final open = ticks[i];
      for (var j = i + 1; j < ticks.length; j++) {
        final close = ticks[j];
        if (close.group(0)!.length != open.group(0)!.length) continue;
        var allVisible = true;
        for (var p = open.start; p < close.end; p++) {
          if (!visible[p]) {
            allVisible = false;
            break;
          }
        }
        if (allVisible) {
          for (var p = open.start; p < close.end; p++) {
            visible[p] = false;
          }
          i = j;
        }
        break;
      }
    }
    return visible;
  }

  static bool _escaped(String text, int offset) {
    var index = offset - 1;
    var count = 0;
    while (index >= 0 && text[index] == '\\') {
      count++;
      index--;
    }
    return count.isOdd;
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
