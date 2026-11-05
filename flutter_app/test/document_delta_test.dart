import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/document_delta.dart';

void main() {
  DocumentDeltaSource source(String id, String content) =>
      DocumentDeltaSource(id: id, title: id, text: content,
          revision: '1', provenance: 'Local test');

  test('exact line differences are labelled without semantic guesses', () {
    final report = DocumentDelta.compare(
      source('old', 'a\nb\nc'), source('new', 'a\nnew\nc'),
    );
    expect(report.added, 1);
    expect(report.removed, 1);
    expect(report.rows.map((x) => x.kind), [
      DocumentDeltaKind.unchanged,
      DocumentDeltaKind.added,
      DocumentDeltaKind.removed,
      DocumentDeltaKind.unchanged,
    ]);
    expect(report.leftFingerprint, isNot(report.rightFingerprint));
  });

  test('identical contents yield zero changes and same fingerprint', () {
    final report = DocumentDelta.compare(
      source('a', 'same'), source('b', 'same'),
    );
    expect(report.added, 0);
    expect(report.removed, 0);
    expect(report.leftFingerprint, report.rightFingerprint);
  });

  test('same revision identity is refused; records are not overwritten', () {
    expect(() => DocumentDelta.compare(
      source('same', 'before'), source('same', 'after'),
    ), throwsFormatException);
  });

  test('bounded input blocks oversized document comparisons', () {
    expect(() => DocumentDelta.compare(
      source('a', 'x' * 50001), source('b', 'ok'),
    ), throwsFormatException);
    expect(() => DocumentDelta.compare(
      source('a', List.filled(241, 'row').join('\n')),
      source('b', 'row'),
    ), throwsFormatException);
    final report = DocumentDelta.compare(
      source('a', List.filled(240, 'row').join('\n')),
      source('b', List.filled(240, 'row').join('\n')),
    );
    expect(report.rows.length, 240);
  });

  test('original texts remain unchanged after comparison', () {
    final a = source('a', 'Original');
    final b = source('b', 'Modified');
    DocumentDelta.compare(a, b);
    expect(a.text, 'Original');
    expect(b.text, 'Modified');
  });
}
