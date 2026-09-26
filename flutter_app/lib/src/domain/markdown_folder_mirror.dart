import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'markdown_interop.dart';
import 'note.dart';

class MarkdownMirrorResult {
  const MarkdownMirrorResult({
    required this.updatedNotes,
    required this.writtenFiles,
    required this.conflicts,
  });

  final List<Note> updatedNotes;
  final int writtenFiles;
  final int conflicts;
}

abstract final class MarkdownFolderMirror {
  static const manifestName = '.notes-ecosistema-sync.json';
  static const manifestVersion = 1;

  static Future<MarkdownMirrorResult> sync(
    String directoryPath,
    List<Note> notes,
  ) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw const FormatException('Cartella Markdown non accessibile.');
    }

    final manifestFile = File('${directory.path}/$manifestName');
    final manifest = await _loadManifest(manifestFile);
    final entries = <String, Map<String, Object?>>{
      for (final raw in (manifest['entries'] as List? ?? const []))
        if (raw is Map && raw['id'] != null)
          raw['id'].toString(): raw.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
    };

    final updated = <Note>[];
    var written = 0;
    var conflicts = 0;
    final nextEntries = <Map<String, Object?>>[];

    for (final note in notes.where(
      (item) => !item.isDeleted && !item.isVisual && !item.isTask,
    )) {
      final previous = entries[note.id];
      final fileName = previous?['file']?.toString() ?? _fileName(note);
      final file = File('${directory.path}/$fileName');
      final local = _documentText(note);
      final base = previous?['base']?.toString() ?? local;
      final external = await file.exists()
          ? await file.readAsString(encoding: utf8)
          : base;

      final resolved = ExternalChangeResolver.resolve(
        base: base,
        local: local,
        external: external,
      );

      var nextNote = note;
      var nextText = local;
      switch (resolved.decision) {
        case ExternalChangeDecision.unchanged:
          nextText = local;
          break;
        case ExternalChangeDecision.takeExternal:
          final parsed = _parseDocument(resolved.text);
          nextNote = note.copyWith(
            title: parsed.title,
            body: parsed.body,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          updated.add(nextNote);
          nextText = _documentText(nextNote);
          break;
        case ExternalChangeDecision.keepLocal:
          nextText = local;
          break;
        case ExternalChangeDecision.conflict:
          final parsed = _parseDocument(resolved.text);
          nextNote = note.copyWith(
            title: parsed.title,
            body: parsed.body,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          );
          updated.add(nextNote);
          conflicts++;
          nextText = _documentText(nextNote);
          break;
      }

      if (!await file.exists() ||
          await file.readAsString(encoding: utf8) != nextText) {
        await _atomicWrite(file, nextText);
        written++;
      }

      nextEntries.add({
        'id': note.id,
        'file': fileName,
        'base': nextText,
        'sha256': sha256.convert(utf8.encode(nextText)).toString(),
      });
    }

    final payload = const JsonEncoder.withIndent('  ').convert({
      'format': 'notes-markdown-folder',
      'version': manifestVersion,
      'entries': nextEntries,
    });
    await _atomicWrite(manifestFile, payload);

    return MarkdownMirrorResult(
      updatedNotes: updated,
      writtenFiles: written,
      conflicts: conflicts,
    );
  }

  static Future<Map<String, Object?>> _loadManifest(File file) async {
    if (!await file.exists()) {
      return const {'entries': <Object?>[]};
    }
    try {
      final text = await file.readAsString(encoding: utf8);
      if (utf8.encode(text).length > 8 * 1024 * 1024) {
        throw const FormatException('Manifest Markdown troppo grande.');
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map ||
          decoded['format'] != 'notes-markdown-folder' ||
          decoded['version'] != manifestVersion ||
          decoded['entries'] is! List) {
        throw const FormatException('Manifest Markdown non valido.');
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Manifest Markdown non leggibile.');
    }
  }

  static String _documentText(Note note) => [
        '# ${note.title.trim().isEmpty ? 'Senza titolo' : note.title.trim()}',
        '',
        note.body,
      ].join('\n').trimRight();

  static ({String title, String body}) _parseDocument(String text) {
    final match = RegExp(r'^#\s+(.+)$', multiLine: true).firstMatch(text);
    final title = match?.group(1)?.trim();
    final body = match == null
        ? text.trim()
        : text.replaceRange(match.start, match.end, '').trim();
    return (
      title: title?.isNotEmpty == true ? title! : 'Senza titolo',
      body: body,
    );
  }

  static String _fileName(Note note) {
    final raw = note.title.trim().isEmpty ? 'nota' : note.title.trim();
    final safe = raw
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '-')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final short = safe.length > 60 ? safe.substring(0, 60).trim() : safe;
    return '${short.isEmpty ? 'nota' : short}--${note.id}.md';
  }

  static Future<void> _atomicWrite(File target, String text) async {
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(text, encoding: utf8, flush: true);
    if (await target.exists()) {
      await target.delete();
    }
    await temp.rename(target.path);
  }
}
