/// Local-only reviewable redaction of plain text. This is not a guarantee
/// against every personal identifier and must not be used as PDF redaction.
class PrivacyCopySource {
  const PrivacyCopySource({
    required this.id,
    required this.title,
    required this.text,
    required this.revision,
  });
  final String id;
  final String title;
  final String text;
  final String revision;
}

enum PrivacyMatchKind { email, iban, possibleMobile }

class PrivacyCopyMatch {
  const PrivacyCopyMatch({
    required this.start,
    required this.end,
    required this.kind,
    required this.value,
  });
  final int start;
  final int end;
  final PrivacyMatchKind kind;
  final String value;
}

abstract final class PrivacyCopy {
  static const maxLength = 50000;
  static const maxHits = 64;
  static final _email = RegExp(
    r'[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9.-]{1,200}\.[A-Za-z]{2,24}',
  );
  static final _iban = RegExp(
    r'IT[0-9]{2}(?:\s?[A-Z0-9]){23}',
    caseSensitive: false,
  );
  static final _mobile = RegExp(
    r'(?:\+39\s?)?3[0-9]{2}[ -]?[0-9]{6,7}',
  );

  static List<PrivacyCopyMatch> scan(String text) {
    if (text.length > maxLength || text.contains('\u0000')) {
      throw const FormatException('PRIVACY_SOURCE_UNSUPPORTED');
    }
    final candidates = <PrivacyCopyMatch>[];
    void addMatches(RegExp exp, PrivacyMatchKind kind,
        {bool Function(String)? accepted}) {
      for (final match in exp.allMatches(text)) {
        final value = text.substring(match.start, match.end);
        if (accepted != null && !accepted(value)) continue;
        candidates.add(PrivacyCopyMatch(
          start: match.start,
          end: match.end,
          kind: kind,
          value: value,
        ));
      }
    }

    addMatches(_email, PrivacyMatchKind.email);
    addMatches(_iban, PrivacyMatchKind.iban, accepted: _validIban);
    addMatches(_mobile, PrivacyMatchKind.possibleMobile);
    candidates.sort((a, b) {
      final start = a.start.compareTo(b.start);
      if (start != 0) return start;
      return b.end.compareTo(a.end);
    });
    final distinct = <PrivacyCopyMatch>[];
    var lastEnd = 0;
    for (final candidate in candidates) {
      if (candidate.start < lastEnd) continue;
      if (distinct.length >= maxHits) {
        throw const FormatException('PRIVACY_TOO_MANY_FINDINGS');
      }
      distinct.add(candidate);
      lastEnd = candidate.end;
    }
    return List.unmodifiable(distinct);
  }

  static String redact(String original, Iterable<int> selectedIndices) {
    final matches = scan(original);
    final selected = selectedIndices.toSet();
    if (selected.any((i) => i < 0 || i >= matches.length)) {
      throw const FormatException('PRIVACY_SELECTION_INVALID');
    }
    final out = StringBuffer();
    var offset = 0;
    for (var i = 0; i < matches.length; i++) {
      final match = matches[i];
      if (!selected.contains(i)) continue;
      out.write(original.substring(offset, match.start));
      out.write('[OSCURATO]');
      offset = match.end;
    }
    out.write(original.substring(offset));
    return out.toString();
  }

  static bool _validIban(String value) {
    final iban = value.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    if (iban.length != 27 || !iban.startsWith('IT')) return false;
    final rearranged = iban.substring(4) + iban.substring(0, 4);
    var remainder = 0;
    for (final unit in rearranged.codeUnits) {
      final ascii = unit >= 65 && unit <= 90;
      if (ascii) {
        final digits = (unit - 55).toString();
        for (final digit in digits.codeUnits) {
          remainder = (remainder * 10 + digit - 48) % 97;
        }
      } else if (unit >= 48 && unit <= 57) {
        remainder = (remainder * 10 + unit - 48) % 97;
      } else {
        return false;
      }
    }
    return remainder == 1;
  }
}
