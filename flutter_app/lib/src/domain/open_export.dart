import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'attachments.dart';
import 'note.dart';
import 'visual_documents.dart';

abstract final class OpenWorkspaceExport {
  static const format = 'notes-open-workspace';
  static const version = 1;
  static const maxArchiveBytes = 96 * 1024 * 1024;

  static Uint8List encode({
    required List<Note> notes,
    required Map<String, Uint8List> assets,
    Map<String, Object?> properties = const {},
    Map<String, Object?> knowledge = const {},
    Map<String, Object?> projects = const {},
    Map<String, Object?> study = const {},
    Map<String, Object?> documents = const {},
    int? exportedAt,
  }) {
    final sorted = [...notes]..sort((a, b) => a.id.compareTo(b.id));
    final archive = Archive();
    final objects = <Map<String, Object?>>[];
    final hashes = <String, String>{};

    for (var index = 0; index < sorted.length; index++) {
      final note = sorted[index];
      final prefix = (index + 1).toString().padLeft(5, '0');
      late final String path;
      late final Uint8List bytes;
      if (note.isVisual) {
        final info = VisualInfo.decode(note.sketchJson!);
        final ext = info.kind == VisualInfoKind.sketch
            ? 'sketch.json'
            : 'whiteboard.json';
        path = 'objects/$prefix-$ext';
        bytes = Uint8List.fromList(utf8.encode(note.body));
      } else {
        path = 'objects/$prefix.md';
        bytes = Uint8List.fromList(
          utf8.encode('# ${note.title}\n\n${_portableBody(note.body)}'),
        );
      }
      archive.add(ArchiveFile.bytes(path, bytes));
      hashes[path] = sha256.convert(bytes).toString();
      objects.add({
        'id': note.id,
        'path': path,
        'type': note.isTask
            ? 'task'
            : note.isVisual
                ? VisualInfo.decode(note.sketchJson!).kind.name
                : 'note',
        'title': note.title,
        'collectionId': note.collectionId,
        'tags': note.tags,
        'createdAt': note.createdAt,
        'updatedAt': note.updatedAt,
        'deletedAt': note.deletedAt,
        'archived': note.archived,
        'favorite': note.favorite,
        'pinned': note.pinned,
        'task': note.taskJson == null ? null : jsonDecode(note.taskJson!),
        'visual': note.sketchJson == null ? null : jsonDecode(note.sketchJson!),
      });
    }

    for (final key in assets.keys.toList()..sort()) {
      final bytes = assets[key]!;
      Attachments.verify(key, bytes);
      final path = 'assets/$key';
      archive.add(ArchiveFile.bytes(path, bytes));
      hashes[path] = sha256.convert(bytes).toString();
    }

    final structured = <String, Map<String, Object?>>{
      'properties': properties,
      'knowledge': knowledge,
      'projects': projects,
      'study': study,
      'documents': documents,
    };
    for (final entry in structured.entries) {
      if (entry.value.isEmpty) continue;
      final path = 'structured/${entry.key}.json';
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(entry.value)));
      archive.add(ArchiveFile.bytes(path, bytes));
      hashes[path] = sha256.convert(bytes).toString();
    }

    final manifest = Uint8List.fromList(
      utf8.encode(
        const JsonEncoder.withIndent('  ').convert({
          'format': format,
          'version': version,
          'exportedAt': exportedAt ?? DateTime.now().millisecondsSinceEpoch,
          'objects': objects,
          'hashes': hashes,
        }),
      ),
    );
    archive.add(ArchiveFile.bytes('manifest.json', manifest));
    archive.add(
      ArchiveFile.string(
        'README.md',
        '# Notes Open Workspace\n\n'
            'Questo archivio è un export aperto e leggibile, non un backup di '
            'disaster recovery. I file Markdown/JSON e gli asset possono essere '
            'usati indipendentemente da Notes. manifest.json conserva gli ID '
            'canonici e le relazioni strutturate disponibili.',
      ),
    );

    final encoded = Uint8List.fromList(ZipEncoder().encodeBytes(archive));
    if (encoded.length > maxArchiveBytes) {
      throw const FormatException('Open Export oltre 96 MiB.');
    }
    return encoded;
  }

  static String _portableBody(String body) => body.replaceAllMapped(
        RegExp(r'notes-asset://([a-f0-9]{64}\.[a-z0-9]{2,4})'),
        (match) => '../assets/${match.group(1)}',
      );
}
