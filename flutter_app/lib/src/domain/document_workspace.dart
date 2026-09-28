import 'dart:convert';

import 'package:crypto/crypto.dart';

enum DocumentAnnotationKind { highlight, note }

class DocumentOcrLayer {
  const DocumentOcrLayer({
    required this.noteId,
    required this.assetKey,
    required this.page,
    required this.originalText,
    required this.sourceFingerprint,
    required this.updatedAt,
    this.correctedText,
  });

  final String noteId;
  final String assetKey;
  final int page;
  final String originalText;
  final String? correctedText;
  final String sourceFingerprint;
  final int updatedAt;

  String get searchableText =>
      correctedText?.trim().isNotEmpty == true ? correctedText! : originalText;

  Map<String, Object?> toMap() => {
        'noteId': noteId,
        'assetKey': assetKey,
        'page': page,
        'originalText': originalText,
        'correctedText': correctedText,
        'sourceFingerprint': sourceFingerprint,
        'updatedAt': updatedAt,
      };

  factory DocumentOcrLayer.fromMap(Map<String, Object?> row) =>
      DocumentOcrLayer(
        noteId: row['noteId']?.toString() ?? '',
        assetKey: row['assetKey']?.toString() ?? '',
        page: (row['page'] as num?)?.toInt() ?? 0,
        originalText: row['originalText']?.toString() ?? '',
        correctedText: row['correctedText']?.toString(),
        sourceFingerprint: row['sourceFingerprint']?.toString() ?? '',
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class DocumentAnnotation {
  const DocumentAnnotation({
    required this.id,
    required this.noteId,
    required this.assetKey,
    required this.page,
    required this.kind,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.text,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String noteId;
  final String assetKey;
  final int page;
  final DocumentAnnotationKind kind;
  final double x;
  final double y;
  final double width;
  final double height;
  final String text;
  final int createdAt;
  final int updatedAt;

  String get anchor =>
      'notes-doc://$noteId/$assetKey?page=$page&annotation=$id';

  Map<String, Object?> toMap() => {
        'id': id,
        'noteId': noteId,
        'assetKey': assetKey,
        'page': page,
        'kind': kind.name,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
        'text': text,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory DocumentAnnotation.fromMap(Map<String, Object?> row) =>
      DocumentAnnotation(
        id: row['id']?.toString() ?? '',
        noteId: row['noteId']?.toString() ?? '',
        assetKey: row['assetKey']?.toString() ?? '',
        page: (row['page'] as num?)?.toInt() ?? 0,
        kind: DocumentAnnotationKind.values.firstWhere(
          (value) => value.name == row['kind']?.toString(),
          orElse: () => DocumentAnnotationKind.note,
        ),
        x: (row['x'] as num?)?.toDouble() ?? 0,
        y: (row['y'] as num?)?.toDouble() ?? 0,
        width: (row['width'] as num?)?.toDouble() ?? 0,
        height: (row['height'] as num?)?.toDouble() ?? 0,
        text: row['text']?.toString() ?? '',
        createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class DocumentSearchHit {
  const DocumentSearchHit({
    required this.noteId,
    required this.assetKey,
    required this.page,
    required this.snippet,
  });

  final String noteId;
  final String assetKey;
  final int page;
  final String snippet;
}

abstract final class DocumentWorkspaceRules {
  static const maxPages = 10000;
  static const maxOcrCharsPerPage = 200000;
  static const maxAnnotationsPerAsset = 10000;

  static String fingerprintBytes(List<int> bytes) =>
      sha256.convert(bytes).toString();

  static void validateOcr(DocumentOcrLayer layer) {
    if (layer.noteId.trim().isEmpty ||
        layer.assetKey.trim().isEmpty ||
        layer.page < 1 ||
        layer.page > maxPages ||
        layer.originalText.length > maxOcrCharsPerPage ||
        (layer.correctedText?.length ?? 0) > maxOcrCharsPerPage ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(layer.sourceFingerprint) ||
        layer.updatedAt < 0) {
      throw const FormatException('Layer OCR non valido.');
    }
  }

  static void validateAnnotation(DocumentAnnotation annotation) {
    bool normalized(double value) => value >= 0 && value <= 1;
    if (annotation.id.trim().isEmpty ||
        annotation.noteId.trim().isEmpty ||
        annotation.assetKey.trim().isEmpty ||
        annotation.page < 1 ||
        annotation.page > maxPages ||
        !normalized(annotation.x) ||
        !normalized(annotation.y) ||
        !normalized(annotation.width) ||
        !normalized(annotation.height) ||
        annotation.x + annotation.width > 1.000001 ||
        annotation.y + annotation.height > 1.000001 ||
        annotation.text.length > 20000 ||
        annotation.createdAt < 0 ||
        annotation.updatedAt < annotation.createdAt) {
      throw const FormatException('Annotazione documento non valida.');
    }
  }

  static Map<String, Object?> exportRecord({
    required List<DocumentOcrLayer> ocr,
    required List<DocumentAnnotation> annotations,
  }) =>
      {
        'version': 1,
        'ocr': ocr.map((item) => item.toMap()).toList(growable: false),
        'annotations':
            annotations.map((item) => item.toMap()).toList(growable: false),
      };

  static String structuredText(DocumentOcrLayer layer) => jsonEncode({
        'page': layer.page,
        'text': layer.searchableText,
        'sourceFingerprint': layer.sourceFingerprint,
        'corrected': layer.correctedText != null,
      });
}
