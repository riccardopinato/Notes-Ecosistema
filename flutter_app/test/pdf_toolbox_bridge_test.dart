import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:notes_ecosistema/src/platform/pdf_toolbox_bridge.dart';

void main() {
  test('header gate accepts only bounded PDF candidate bytes', () {
    final good = Uint8List.fromList('%PDF-1.7'.codeUnits);
    final other = Uint8List.fromList('NOTPDF!'.codeUnits);
    expect(PdfToolboxBridge.validPdfBytes(good), isTrue);
    expect(PdfToolboxBridge.validPdfBytes(other), isFalse);
    expect(PdfToolboxBridge.validPdfBytes(Uint8List(0)), isFalse);
    expect(
        PdfToolboxBridge.validPdfBytes(
          Uint8List(PdfToolboxBridge.maxInputBytes + 1),
        ),
        isFalse);
  });

  test('range, rotation and page sequence are prevalidated', () {
    for (final pair in [(0, 1), (2, 1), (1, 201)]) {
      expect(
        () => PdfToolboxRequest(
          operation: PdfToolboxOperation.extractRange,
          firstPage: pair.$1,
          lastPage: pair.$2,
        ).validate(),
        throwsFormatException,
      );
    }
    expect(
      () => const PdfToolboxRequest(
        operation: PdfToolboxOperation.rotate,
        degrees: 13,
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const PdfToolboxRequest(
        operation: PdfToolboxOperation.reorder,
        order: [1, 1],
      ).validate(),
      throwsFormatException,
    );
    const PdfToolboxRequest(
      operation: PdfToolboxOperation.extractRange,
      firstPage: 1,
      lastPage: 2,
    ).validate();
    const PdfToolboxRequest(
      operation: PdfToolboxOperation.merge,
    ).validate();
  });
}
