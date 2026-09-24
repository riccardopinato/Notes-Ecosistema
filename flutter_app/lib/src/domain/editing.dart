enum MarkdownAction {
  bold,
  italic,
  heading,
  bullet,
  numbered,
  quote,
  code,
  codeBlock,
}

class MarkdownEdit {
  const MarkdownEdit(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;
}

abstract final class MarkdownEditing {
  static const _grave = 0x60;

  static MarkdownEdit apply(
    String text,
    int start,
    int end,
    MarkdownAction action,
  ) {
    final a = start < end
        ? start.clamp(0, text.length).toInt()
        : end.clamp(0, text.length).toInt();
    final b = start < end
        ? end.clamp(a, text.length).toInt()
        : start.clamp(a, text.length).toInt();
    final chosen = text.substring(a, b);

    MarkdownEdit wrap(String left, [String? right]) {
      final suffix = right ?? left;
      final inner = chosen.isEmpty ? 'testo' : chosen;
      final replacement = '$left$inner$suffix';
      return MarkdownEdit(
        text.replaceRange(a, b, replacement),
        a + left.length,
        a + left.length + inner.length,
      );
    }

    switch (action) {
      case MarkdownAction.bold:
        return wrap('**');
      case MarkdownAction.italic:
        return wrap('*');
      case MarkdownAction.code:
        if (chosen.contains('\n') || chosen.contains('\r')) {
          throw const FormatException('Per più righe usa Blocco codice.');
        }
        final runs = RegExp(r'\x60+').allMatches(chosen);
        var longest = 0;
        for (final run in runs) {
          if (run.group(0)!.length > longest) longest = run.group(0)!.length;
        }
        final fence =
            String.fromCharCodes(List<int>.filled(longest + 1, _grave));
        final grave = String.fromCharCode(_grave);
        final padding = chosen.startsWith(grave) ||
                chosen.endsWith(grave) ||
                (chosen.startsWith(' ') && chosen.endsWith(' '))
            ? ' '
            : '';
        return wrap('$fence$padding', '$padding$fence');
      case MarkdownAction.codeBlock:
        final newline = text.contains('\r\n') ? '\r\n' : '\n';
        final runs = RegExp(r'\x60+').allMatches(chosen);
        var longest = 0;
        for (final run in runs) {
          if (run.group(0)!.length > longest) longest = run.group(0)!.length;
        }
        final fenceLength = (longest + 1).clamp(3, 1000).toInt();
        final fence =
            String.fromCharCodes(List<int>.filled(fenceLength, _grave));
        final before = a > 0 && text.codeUnitAt(a - 1) != 10 ? newline : '';
        final after = b < text.length &&
                text.codeUnitAt(b) != 10 &&
                text.codeUnitAt(b) != 13
            ? newline
            : '';
        return wrap('$before$fence$newline', '$newline$fence$after');
      case MarkdownAction.heading:
      case MarkdownAction.bullet:
      case MarkdownAction.numbered:
      case MarkdownAction.quote:
        final lineStart = a == 0 ? 0 : text.lastIndexOf('\n', a - 1) + 1;
        final last = b > a && text.codeUnitAt(b - 1) == 10 ? b - 1 : b;
        final foundEnd = text.indexOf('\n', last);
        final lineEnd = foundEnd < 0 ? text.length : foundEnd;
        final lines = text.substring(lineStart, lineEnd).split('\n');
        final replacement = <String>[];
        for (var index = 0; index < lines.length; index++) {
          final prefix = switch (action) {
            MarkdownAction.heading => '## ',
            MarkdownAction.bullet => '- ',
            MarkdownAction.numbered => '${index + 1}. ',
            MarkdownAction.quote => '> ',
            _ => '',
          };
          replacement.add('$prefix${lines[index]}');
        }
        final value = replacement.join('\n');
        return MarkdownEdit(
          text.replaceRange(lineStart, lineEnd, value),
          lineStart,
          lineStart + value.length,
        );
    }
  }

  static MarkdownEdit link(
    String text,
    int start,
    int end,
    String label,
    String url,
  ) {
    final cleanUrl = url.trim();
    final uri = Uri.tryParse(cleanUrl);
    if (uri == null ||
        !const {'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Inserisci un link http o https valido.');
    }
    if (label.trim().isEmpty || label.contains('\n') || label.contains('\r')) {
      throw const FormatException(
        'Inserisci un testo del link su una sola riga.',
      );
    }

    final a = start < end
        ? start.clamp(0, text.length).toInt()
        : end.clamp(0, text.length).toInt();
    final b = start < end
        ? end.clamp(a, text.length).toInt()
        : start.clamp(a, text.length).toInt();
    final safeLabel = label
        .replaceAll('\\', '\\\\')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]');
    final result = '[$safeLabel](<${uri.toString()}>)';
    return MarkdownEdit(
      text.replaceRange(a, b, result),
      a + result.length,
      a + result.length,
    );
  }
}

class ChecklistItem {
  const ChecklistItem({
    required this.lineIndex,
    required this.markerOffset,
    required this.label,
    required this.completed,
    this.depth = 0,
    this.parentLine,
  });

  final int lineIndex;
  final int markerOffset;
  final String label;
  final bool completed;
  final int depth;
  final int? parentLine;
}

abstract final class Checklist {
  static final _task = RegExp(
    r'^( {0,3}[-*+]\s+\[)([ xX])\]\s+(.*)$',
  );

  static bool hasMarker(String body, {int maxChars = 12000}) {
    final source = body.length <= maxChars ? body : body.substring(0, maxChars);
    for (final line in source.split(RegExp(r'\r?\n'))) {
      final value = line.trimLeft().toLowerCase();
      if (value.startsWith('- [ ] ') ||
          value.startsWith('- [x] ') ||
          value.startsWith('* [ ] ') ||
          value.startsWith('* [x] ')) {
        return true;
      }
    }
    return false;
  }

  static List<ChecklistItem> parse(String body) => _scan(body).items;

  static String setCompleted(
    String body,
    int lineIndex,
    bool completed,
  ) {
    ChecklistItem? item;
    for (final candidate in parse(body)) {
      if (candidate.lineIndex == lineIndex) {
        item = candidate;
        break;
      }
    }
    if (item == null) {
      throw const FormatException(
        'L’attività è cambiata. Riapri la nota.',
      );
    }
    return body.replaceRange(
      item.markerOffset,
      item.markerOffset + 1,
      completed ? 'x' : ' ',
    );
  }

  static String append(String body, String label) {
    final clean = label.trim();
    if (clean.isEmpty || clean.contains('\n') || clean.contains('\r')) {
      throw const FormatException(
        'Scrivi un’attività su una sola riga.',
      );
    }
    if (_scan(body).openFence) {
      throw const FormatException(
        'Chiudi il blocco di codice in modalità Testo prima di aggiungere attività.',
      );
    }
    final newline = body.contains('\r\n') ? '\r\n' : '\n';
    final separator = body.isEmpty || body.endsWith('\n') || body.endsWith('\r')
        ? ''
        : newline;
    return '$body$separator- [ ] $clean';
  }

  static _ChecklistScan _scan(String body) {
    final result = <ChecklistItem>[];
    String? fenceChar;
    var fenceLength = 0;
    var globalOffset = 0;
    final rawLines = body.split('\n');

    for (var lineIndex = 0; lineIndex < rawLines.length; lineIndex++) {
      final raw = rawLines[lineIndex];
      final text = raw.endsWith('\r') ? raw.substring(0, raw.length - 1) : raw;
      final indent = text.length - text.trimLeft().length;
      final trimmed = text.substring(indent);
      final char = trimmed.isEmpty ? null : trimmed[0];
      var length = 0;
      if (char == String.fromCharCode(0x60) || char == '~') {
        while (length < trimmed.length && trimmed[length] == char) {
          length++;
        }
      }

      if (indent <= 3 && length >= 3) {
        if (fenceChar == null) {
          fenceChar = char;
          fenceLength = length;
        } else if (fenceChar == char &&
            length >= fenceLength &&
            trimmed.substring(length).trim().isEmpty) {
          fenceChar = null;
          fenceLength = 0;
        }
      } else if (fenceChar == null) {
        final match = _task.firstMatch(text);
        if (match != null) {
          final label = (match.group(3) ?? '').trim();
          if (label.isNotEmpty) {
            final previous =
                result.isNotEmpty && result.last.lineIndex == lineIndex - 1
                    ? result.last
                    : null;
            final parent = indent >= 2 && previous != null
                ? previous.parentLine ?? previous.lineIndex
                : null;
            result.add(
              ChecklistItem(
                lineIndex: lineIndex,
                markerOffset:
                    globalOffset + match.start + match.group(1)!.length,
                label: label,
                completed: match.group(2) != ' ',
                depth: parent == null ? 0 : 1,
                parentLine: parent,
              ),
            );
          }
        }
      }

      globalOffset += raw.length + (lineIndex < rawLines.length - 1 ? 1 : 0);
    }

    return _ChecklistScan(result, fenceChar != null);
  }
}

class _ChecklistScan {
  const _ChecklistScan(this.items, this.openFence);
  final List<ChecklistItem> items;
  final bool openFence;
}

abstract final class NoteTags {
  static const maxPerNote = 20;

  static String name(String raw) {
    var value = raw.trim();
    if (value.startsWith('#')) value = value.substring(1);
    value = value.toLowerCase();
    final valid = RegExp(
      r'^[\p{L}\p{M}\p{N}_-]+$',
      unicode: true,
    ).hasMatch(value);
    if (value.isEmpty || value.length > 40 || !valid) {
      throw const FormatException(
        'Tag: da 1 a 40 caratteri, lettere, numeri, trattino o underscore.',
      );
    }
    return value;
  }

  static List<String> normalize(Iterable<String> values) {
    final source = values.toList(growable: false);
    if (source.length > maxPerNote) {
      throw const FormatException('Massimo 20 tag per nota.');
    }
    final result = source.map(name).toSet().toList()..sort();
    return result;
  }

  static List<String> add(List<String> values, String raw) {
    final next = [...normalize(values), name(raw)];
    return normalize(next);
  }
}
