import 'dart:convert';
import 'package:crypto/crypto.dart';

enum DocumentDeltaKind { unchanged, added, removed }

class DocumentDeltaSource {
  const DocumentDeltaSource({
    required this.id,
    required this.title,
    required this.text,
    required this.revision,
    required this.provenance,
  });
  final String id;
  final String title;
  final String text;
  final String revision;
  final String provenance;

  String get fingerprint => sha256.convert(utf8.encode(text)).toString();
}

class DocumentDeltaRow {
  const DocumentDeltaRow(this.kind, this.text);
  final DocumentDeltaKind kind;
  final String text;
}

class DocumentDeltaReport {
  const DocumentDeltaReport({
    required this.leftFingerprint,
    required this.rightFingerprint,
    required this.rows,
    required this.added,
    required this.removed,
  });
  final String leftFingerprint;
  final String rightFingerprint;
  final List<DocumentDeltaRow> rows;
  final int added;
  final int removed;
}

/// Pure line diff: labels every changed line rather than hallucinating a
/// semantic change. Memory bounded by 240 x 240 comparisons.
abstract final class DocumentDelta {
  static const maxChars = 50000;
  static const maxLines = 240;

  static DocumentDeltaReport compare(
      DocumentDeltaSource before, DocumentDeltaSource after) {
    if (before.id == after.id ||
        before.text.length > maxChars ||
        after.text.length > maxChars) {
      throw const FormatException('DOCUMENT_DELTA_INVALID_SOURCES');
    }
    final left = before.text.replaceAll('\r\n', '\n').split('\n');
    final right = after.text.replaceAll('\r\n', '\n').split('\n');
    if (left.length > maxLines || right.length > maxLines) {
      throw const FormatException('DOCUMENT_DELTA_TOO_MANY_LINES');
    }
    final dp = List.generate(
      left.length + 1, (_) => List<int>.filled(right.length + 1, 0),
      growable: false,
    );
    for (var a = left.length - 1; a >= 0; a--) {
      for (var b = right.length - 1; b >= 0; b--) {
        dp[a][b] = left[a] == right[b]
            ? 1 + dp[a + 1][b + 1]
            : (dp[a + 1][b] >= dp[a][b + 1]
                ? dp[a + 1][b] : dp[a][b + 1]);
      }
    }
    var a = 0;
    var b = 0;
    var added = 0;
    var removed = 0;
    final rows = <DocumentDeltaRow>[];
    while (a < left.length || b < right.length) {
      if (a < left.length && b < right.length &&
          left[a] == right[b]) {
        rows.add(DocumentDeltaRow(DocumentDeltaKind.unchanged, left[a]));
        a++;
        b++;
      } else if (b < right.length &&
          (a == left.length || dp[a][b + 1] >= dp[a + 1][b])) {
        rows.add(DocumentDeltaRow(DocumentDeltaKind.added, right[b]));
        b++;
        added++;
      } else {
        rows.add(DocumentDeltaRow(DocumentDeltaKind.removed, left[a]));
        a++;
        removed++;
      }
    }
    return DocumentDeltaReport(
      leftFingerprint: before.fingerprint,
      rightFingerprint: after.fingerprint,
      rows: List.unmodifiable(rows),
      added: added,
      removed: removed,
    );
  }
}
