import 'dart:convert';

class CaptureSeed {
  const CaptureSeed({
    this.title = '',
    this.body = '',
    this.checklist = false,
  });

  final String title;
  final String body;
  final bool checklist;

  bool get hasContent => title.trim().isNotEmpty || body.trim().isNotEmpty;
}

abstract final class QuickCapture {
  static const maxBytes = 200 * 1024;

  static CaptureSeed shared(String? text, String? subject) {
    final body = text ?? '';
    final title = (subject ?? '').trim();
    if (title.length > 8000) {
      throw const FormatException('Il titolo condiviso è troppo lungo.');
    }
    if (utf8.encode(title).length + utf8.encode(body).length > maxBytes) {
      throw const FormatException('Testo condiviso oltre 200 KB.');
    }
    if (title.contains('\u0000') || body.contains('\u0000')) {
      throw const FormatException('Il contenuto non è testo valido.');
    }
    final seed = CaptureSeed(title: title, body: body);
    if (!seed.hasContent) {
      throw const FormatException(
        'Nessun testo da aggiungere. Condividi un testo o un link.',
      );
    }
    return seed;
  }
}

class SharedCaptureFile {
  const SharedCaptureFile({
    required this.path,
    required this.name,
    required this.mime,
  });

  final String path;
  final String name;
  final String mime;

  factory SharedCaptureFile.fromMap(Map<Object?, Object?> map) =>
      SharedCaptureFile(
        path: map['path']?.toString() ?? '',
        name: map['name']?.toString() ?? 'Allegato',
        mime: map['mime']?.toString() ?? '',
      );
}

class IncomingCapture {
  const IncomingCapture({
    required this.seed,
    this.files = const [],
  });

  final CaptureSeed seed;
  final List<SharedCaptureFile> files;

  bool get empty => !seed.hasContent && files.isEmpty;

  factory IncomingCapture.fromMap(Map<Object?, Object?> map) {
    final rawFiles = map['files'];
    return IncomingCapture(
      seed: CaptureSeed(
        title: map['title']?.toString() ?? '',
        body: map['body']?.toString() ?? '',
        checklist: map['checklist'] == true,
      ),
      files: rawFiles is List
          ? rawFiles
              .whereType<Map>()
              .map(
                (item) => SharedCaptureFile.fromMap(
                  item.cast<Object?, Object?>(),
                ),
              )
              .toList(growable: false)
          : const [],
    );
  }
}
