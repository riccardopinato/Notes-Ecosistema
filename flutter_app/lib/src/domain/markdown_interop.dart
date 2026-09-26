import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'note.dart';
import 'planner.dart';
import 'research.dart';

class MarkdownPortableDocument {
  const MarkdownPortableDocument({
    required this.fileName,
    required this.title,
    required this.body,
    this.sourceId,
    this.tags = const [],
    this.taskJson,
  });

  final String fileName;
  final String title;
  final String body;
  final String? sourceId;
  final List<String> tags;
  final String? taskJson;

  bool get isTask => taskJson != null && taskJson!.trim().isNotEmpty;
}

enum ExternalChangeDecision {
  unchanged,
  takeExternal,
  keepLocal,
  conflict,
}

class ExternalMergeResult {
  const ExternalMergeResult(this.decision, this.text);

  final ExternalChangeDecision decision;
  final String text;
}

abstract final class ExternalChangeResolver {
  static ExternalMergeResult resolve({
    required String base,
    required String local,
    required String external,
  }) {
    if (local == external) {
      return ExternalMergeResult(ExternalChangeDecision.unchanged, local);
    }
    if (local == base) {
      return ExternalMergeResult(ExternalChangeDecision.takeExternal, external);
    }
    if (external == base) {
      return ExternalMergeResult(ExternalChangeDecision.keepLocal, local);
    }
    return ExternalMergeResult(
      ExternalChangeDecision.conflict,
      [
        local.trimRight(),
        '',
        '<!-- EXTERNAL CHANGE CONFLICT: local preserved above -->',
        '',
        '## Versione esterna preservata',
        '',
        external.trimRight(),
      ].join('\n'),
    );
  }
}

abstract final class MarkdownWorkspaceBundle {
  static const format = 'notes-markdown-workspace';
  static const version = 1;
  static const maxBytes = 32 * 1024 * 1024;
  static const maxDocuments = 10000;

  static Uint8List encode(
    List<Note> notes, {
    Map<String, SyncedBlock> syncedBlocks = const {},
  }) {
    final portable = notes
        .where((note) => !note.isDeleted && !note.isVisual)
        .toList(growable: false);
    if (portable.length > maxDocuments) {
      throw const FormatException(
        'Il workspace supera il limite di 10.000 documenti Markdown.',
      );
    }
    final archive = Archive();
    final manifest = <Map<String, Object?>>[];
    final used = <String>{};

    for (var index = 0; index < portable.length; index++) {
      final note = portable[index];
      final base = _safeName(
        note.title.trim().isEmpty ? 'senza-titolo' : note.title.trim(),
      );
      var name = '$base.md';
      var suffix = 2;
      while (!used.add(name.toLowerCase())) {
        name = '$base-$suffix.md';
        suffix++;
      }
      final materializedBody =
          SyncedBlockCodec.resolve(note.body, syncedBlocks);
      if (SyncedBlockCodec.marker.hasMatch(materializedBody)) {
        throw FormatException(
          'La nota "${note.title}" contiene un Synced Block non disponibile.',
        );
      }
      final text = [
        '---',
        'notes_source_id: ${note.id}',
        'notes_kind: ${note.isTask ? 'task' : 'note'}',
        if (note.tags.isNotEmpty) 'tags: ${jsonEncode(note.tags)}',
        if (note.taskJson?.trim().isNotEmpty == true)
          'notes_task_json_b64: ${base64Url.encode(utf8.encode(note.taskJson!))}',
        '---',
        '',
        '# ${note.title.trim().isEmpty ? 'Senza titolo' : note.title.trim()}',
        '',
        materializedBody,
      ].join('\n');
      archive.add(ArchiveFile.string('notes/$name', text));
      manifest.add({
        'file': 'notes/$name',
        'id': note.id,
        'title': note.title,
      });
    }

    archive.add(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'format': format,
          'version': version,
          'documents': manifest,
        }),
      ),
    );
    archive.add(
      ArchiveFile.string(
        'README.txt',
        'Export Markdown portabile di Notes Ecosistema. '
            'I file in notes/ restano Markdown leggibile senza Notes.',
      ),
    );

    final bytes = ZipEncoder().encodeBytes(archive);
    if (bytes.length > maxBytes) {
      throw const FormatException('Export Markdown oltre 32 MiB.');
    }
    return Uint8List.fromList(bytes);
  }

  static List<MarkdownPortableDocument> decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const FormatException('Archivio Markdown non valido.');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.length > maxDocuments + 10) {
      throw const FormatException('Troppi file Markdown.');
    }
    final result = <MarkdownPortableDocument>[];
    final seen = <String>{};
    var expanded = 0;

    for (final entry in archive) {
      if (!entry.isFile || !seen.add(entry.name)) {
        throw const FormatException('Voce ZIP duplicata o non valida.');
      }
      final allowed = entry.name == 'manifest.json' ||
          entry.name == 'README.txt' ||
          RegExp(r'^notes/[^/]+\.(md|txt)$', caseSensitive: false)
              .hasMatch(entry.name);
      if (!allowed) {
        throw const FormatException('Percorso Markdown non consentito.');
      }
      final data = entry.readBytes();
      if (data == null) {
        throw const FormatException('File Markdown non leggibile.');
      }
      expanded += data.length;
      if (expanded > maxBytes) {
        throw const FormatException('Archivio Markdown espanso oltre 32 MiB.');
      }
      if (!entry.name.startsWith('notes/')) continue;

      var text = utf8.decode(data, allowMalformed: false);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      final parsed = _parseFrontMatter(text);
      final body = parsed.body;
      final titleMatch =
          RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(body);
      final title = titleMatch?.group(1)?.trim() ??
          entry.name.split('/').last.replaceFirst(RegExp(r'\.(md|txt)$'), '');
      final cleanBody = titleMatch == null
          ? body.trim()
          : body.replaceRange(titleMatch.start, titleMatch.end, '').trim();
      result.add(
        MarkdownPortableDocument(
          fileName: entry.name,
          title: title,
          body: cleanBody,
          sourceId: parsed.sourceId,
          tags: parsed.tags,
          taskJson: parsed.taskJson,
        ),
      );
      if (result.length > maxDocuments) {
        throw const FormatException('Troppi documenti Markdown.');
      }
    }
    return result;
  }

  static ({
    String body,
    String? sourceId,
    List<String> tags,
    String? taskJson,
  }) _parseFrontMatter(String text) {
    if (!text.startsWith('---\n')) {
      return (body: text, sourceId: null, tags: const [], taskJson: null);
    }
    final end = text.indexOf('\n---\n', 4);
    if (end < 0 || end > 10000) {
      return (body: text, sourceId: null, tags: const [], taskJson: null);
    }
    final header = text.substring(4, end);
    String? field(String name) => RegExp(
          '^${RegExp.escape(name)}:\\s*(.+?)\\s*\$',
          multiLine: true,
        ).firstMatch(header)?.group(1);

    final sourceId = field('notes_source_id');
    final kind = field('notes_kind')?.trim().toLowerCase();
    var tags = const <String>[];
    final tagsRaw = field('tags');
    if (tagsRaw != null) {
      try {
        final decoded = jsonDecode(tagsRaw);
        if (decoded is! List) {
          throw const FormatException('Tag Markdown non validi.');
        }
        tags = decoded
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false);
      } catch (_) {
        throw const FormatException('Tag Markdown non validi.');
      }
    }

    String? taskJson;
    final taskRaw = field('notes_task_json_b64');
    if (kind == 'task') {
      if (taskRaw != null && taskRaw.isNotEmpty) {
        try {
          taskJson = utf8.decode(base64Url.decode(taskRaw));
          TaskDetails.decode(taskJson);
        } catch (_) {
          throw const FormatException('Metadati attività Markdown non validi.');
        }
      } else {
        taskJson = TaskDetails.empty().encode();
      }
    }

    return (
      body: text.substring(end + 5),
      sourceId: sourceId,
      tags: tags,
      taskJson: taskJson,
    );
  }

  static String _safeName(String input) {
    final normalized = input
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .replaceAll(RegExp(r'[. ]+$'), '');
    final safe = normalized.isEmpty ? 'nota' : normalized;
    return safe.length > 90 ? safe.substring(0, 90).trim() : safe;
  }
}
