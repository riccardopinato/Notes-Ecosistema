import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum PdfToolboxOperation { extractRange, merge, rotate, reorder }

class PdfToolboxRequest {
  const PdfToolboxRequest({
    required this.operation,
    this.firstPage,
    this.lastPage,
    this.degrees = 90,
    this.order = const [],
  });

  final PdfToolboxOperation operation;
  final int? firstPage;
  final int? lastPage;
  final int degrees;
  final List<int> order;

  void validate() {
    switch (operation) {
      case PdfToolboxOperation.extractRange:
        if (firstPage == null ||
            lastPage == null ||
            firstPage! < 1 ||
            lastPage! < firstPage! ||
            lastPage! > 200) {
          throw const FormatException('PDF_RANGE_INVALID');
        }
        return;
      case PdfToolboxOperation.merge:
        return;
      case PdfToolboxOperation.rotate:
        if (!const [90, 180, 270].contains(degrees)) {
          throw const FormatException('PDF_ROTATION_INVALID');
        }
        return;
      case PdfToolboxOperation.reorder:
        if (order.isEmpty ||
            order.length > 200 ||
            order.any((value) => value < 1 || value > 200) ||
            order.toSet().length != order.length) {
          throw const FormatException('PDF_ORDER_INVALID');
        }
        return;
    }
  }
}

/// Local Android PDF tool; returns a new copy, never mutates the CAS input.
abstract final class PdfToolboxBridge {
  static const _channel = MethodChannel('notes.ecosystem/pdf_toolbox');
  static const maxInputBytes = 16 * 1024 * 1024;
  static const maxOutputBytes = 32 * 1024 * 1024;

  static bool validPdfBytes(Uint8List bytes) =>
      bytes.length >= 5 &&
      bytes.length <= maxInputBytes &&
      bytes[0] == 0x25 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x44 &&
      bytes[3] == 0x46 &&
      bytes[4] == 0x2d;

  static Future<Uint8List> transform({
    required PdfToolboxRequest request,
    required Uint8List source,
    Uint8List? secondary,
  }) async {
    request.validate();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw const FormatException('PDF_ANDROID_ONLY');
    }
    if (!validPdfBytes(source) ||
        (request.operation == PdfToolboxOperation.merge &&
            (secondary == null || !validPdfBytes(secondary)))) {
      throw const FormatException('PDF_INPUT_UNSUPPORTED');
    }
    final bytes = await _channel.invokeMethod<Uint8List>('transform', {
      'action': request.operation.name,
      'source': source,
      'secondary': secondary,
      'first': request.firstPage,
      'last': request.lastPage,
      'degrees': request.degrees,
      'order': request.order,
    });
    if (bytes == null ||
        bytes.length > maxOutputBytes ||
        bytes.length < 5 ||
        bytes[0] != 0x25 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x44 ||
        bytes[3] != 0x46 ||
        bytes[4] != 0x2d) {
      throw const FormatException('PDF_OUTPUT_UNSUPPORTED');
    }
    return bytes;
  }
}
