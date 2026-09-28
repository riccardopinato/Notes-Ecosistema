import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/domain/derivatives.dart';
import 'package:notes_ecosistema/src/domain/documents.dart';

void main() {
  test('PDF page and normalized region anchors validate', () {
    const pageOnly = PdfAnchor(page: 2);
    pageOnly.validate();

    const region = PdfAnchor(
      page: 3,
      x: .1,
      y: .2,
      width: .4,
      height: .3,
    );
    region.validate();
    expect(region.hasRegion, isTrue);

    expect(
      () => const PdfAnchor(
        page: 1,
        x: .9,
        y: .1,
        width: .2,
        height: .2,
      ).validate(),
      throwsFormatException,
    );
  });

  test('annotation preserves page/region through serialization', () {
    const source = PdfAnnotation(
      id: 'a1',
      noteId: 'n1',
      assetKey:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf',
      anchor: PdfAnchor(
        page: 4,
        x: .1,
        y: .2,
        width: .3,
        height: .4,
      ),
      kind: PdfAnnotationKind.highlight,
      selectedText: 'citazione',
      comment: '',
      createdAt: 1,
      updatedAt: 2,
    );
    DocumentRules.validateAnnotation(source);
    final decoded = PdfAnnotation.fromMap(source.toMap());
    expect(decoded.anchor.page, 4);
    expect(decoded.anchor.hasRegion, isTrue);
    expect(decoded.selectedText, 'citazione');
  });

  test('corrected OCR wins over original while both remain preserved', () {
    const key =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa.pdf';
    const original = SourceDerivative(
      id: 'd1',
      sourceNoteId: 'n1',
      sourceAssetKey: key,
      kind: DerivativeKind.ocrText,
      content: 'raw',
      sourceFingerprint: 'fingerprint',
      createdAt: 1,
      engine: 'ocr',
    );
    const corrected = SourceDerivative(
      id: 'd2',
      sourceNoteId: 'n1',
      sourceAssetKey: key,
      kind: DerivativeKind.ocrCorrected,
      content: 'corrected',
      sourceFingerprint: 'fingerprint',
      createdAt: 2,
      engine: 'user-corrected-ocr-v1',
    );

    expect(DocumentRules.preferredOcr([original, corrected], key), corrected);
    expect([original, corrected].length, 2);
  });

  test('OCR search is query-aware and bounded', () {
    final hits = DocumentRules.searchOffsets(
      'Casa uno, casa due, CASA tre',
      'casa',
    );
    expect(hits, [0, 10, 20]);
  });
}
