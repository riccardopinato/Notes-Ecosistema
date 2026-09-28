import 'derivatives.dart';

enum PdfAnnotationKind { highlight, comment }

class PdfAnchor {
  const PdfAnchor({
    required this.page,
    this.x,
    this.y,
    this.width,
    this.height,
  });

  final int page;
  final double? x;
  final double? y;
  final double? width;
  final double? height;

  bool get hasRegion =>
      x != null && y != null && width != null && height != null;

  Map<String, Object?> toMap() => {
        'page': page,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      };

  factory PdfAnchor.fromMap(Map<String, Object?> row) => PdfAnchor(
        page: (row['page'] as num?)?.toInt() ?? 0,
        x: (row['x'] as num?)?.toDouble(),
        y: (row['y'] as num?)?.toDouble(),
        width: (row['width'] as num?)?.toDouble(),
        height: (row['height'] as num?)?.toDouble(),
      );

  void validate() {
    if (page < 1) {
      throw const FormatException('Pagina PDF non valida.');
    }
    final values = [x, y, width, height];
    final present = values.where((value) => value != null).length;
    if (present != 0 && present != 4) {
      throw const FormatException('Regione PDF incompleta.');
    }
    if (present == 4) {
      if (x! < 0 ||
          y! < 0 ||
          width! <= 0 ||
          height! <= 0 ||
          x! > 1 ||
          y! > 1 ||
          width! > 1 ||
          height! > 1 ||
          x! + width! > 1.000001 ||
          y! + height! > 1.000001) {
        throw const FormatException('Regione PDF fuori pagina.');
      }
    }
  }
}

class PdfAnnotation {
  const PdfAnnotation({
    required this.id,
    required this.noteId,
    required this.assetKey,
    required this.anchor,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    this.selectedText = '',
    this.comment = '',
  });

  final String id;
  final String noteId;
  final String assetKey;
  final PdfAnchor anchor;
  final PdfAnnotationKind kind;
  final String selectedText;
  final String comment;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'noteId': noteId,
        'assetKey': assetKey,
        'page': anchor.page,
        'x': anchor.x,
        'y': anchor.y,
        'width': anchor.width,
        'height': anchor.height,
        'kind': kind.name,
        'selectedText': selectedText,
        'comment': comment,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory PdfAnnotation.fromMap(Map<String, Object?> row) {
    final rawKind = row['kind']?.toString() ?? '';
    final kinds =
        PdfAnnotationKind.values.where((value) => value.name == rawKind);
    if (kinds.isEmpty) {
      throw const FormatException('Tipo annotazione PDF non valido.');
    }
    return PdfAnnotation(
      id: row['id']?.toString() ?? '',
      noteId: row['noteId']?.toString() ?? '',
      assetKey: row['assetKey']?.toString() ?? '',
      anchor: PdfAnchor.fromMap(row),
      kind: kinds.first,
      selectedText: row['selectedText']?.toString() ?? '',
      comment: row['comment']?.toString() ?? '',
      createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
      updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract final class DocumentRules {
  static const maxAnnotationsPerAsset = 2000;
  static const maxSelectedText = 12000;
  static const maxComment = 24000;

  static void validateAnnotation(PdfAnnotation item) {
    item.anchor.validate();
    if (item.id.trim().isEmpty ||
        item.noteId.trim().isEmpty ||
        item.assetKey.trim().isEmpty ||
        item.selectedText.length > maxSelectedText ||
        item.comment.length > maxComment ||
        item.createdAt < 0 ||
        item.updatedAt < 0 ||
        (item.kind == PdfAnnotationKind.highlight &&
            item.selectedText.trim().isEmpty &&
            !item.anchor.hasRegion) ||
        (item.kind == PdfAnnotationKind.comment &&
            item.comment.trim().isEmpty)) {
      throw const FormatException('Annotazione PDF non valida.');
    }
  }

  static SourceDerivative? preferredOcr(
    Iterable<SourceDerivative> derivatives,
    String assetKey,
  ) {
    final candidates = derivatives
        .where(
          (item) =>
              item.sourceAssetKey == assetKey &&
              (item.kind == DerivativeKind.ocrText ||
                  item.kind == DerivativeKind.ocrCorrected),
        )
        .toList(growable: false)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    for (final item in candidates) {
      if (item.kind == DerivativeKind.ocrCorrected) return item;
    }
    return candidates.isEmpty ? null : candidates.first;
  }

  static List<int> searchOffsets(String text, String query, {int limit = 200}) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    final haystack = text.toLowerCase();
    final offsets = <int>[];
    var from = 0;
    while (offsets.length < limit) {
      final index = haystack.indexOf(needle, from);
      if (index < 0) break;
      offsets.add(index);
      from = index + needle.length;
    }
    return offsets;
  }
}
