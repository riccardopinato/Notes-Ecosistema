import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'markdown_interop.dart';
import 'note.dart';

class MarkdownMirrorResult {
  const MarkdownMirrorResult({
    required this.updatedNotes,
    required this.writtenFiles,
    required this.conflicts,
    required this.manifestPayload,
  });

  final List<Note> updatedNotes;
  final int writtenFiles;
  final int conflicts;

  /// Pending manifest. It must be finalized only after [updatedNotes] have
  /// been committed to the canonical Notes database.
  final String manifestPayload;
}

class _MirrorPlan {
  const _MirrorPlan({
    required this.file,
    required this.text,
    required this.needsWrite,
  });

  final File file;
  final String text;
  final bool needsWrite;
}

abstract final class MarkdownFolderMirror {
  static const manifestName = '.notes-ecosistema-sync.json';
  static const manifestVersion = 1;
  static const maxManifestBytes = 8 * 1024 * 1024;

  static Future<MarkdownMirrorResult> sync(
    String directoryPath,
    List<Note> notes,
  ) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw const FormatException('Cartella Markdown non accessibile.');
    }

    final manifestFile = File(p.join(directory.path, manifestName));
    final manifestExists = await manifestFile.exists();
    final manifest = await _loadManifest(manifestFile);
    final entries = <String, Map<String, Object?>>{
      for (final raw in (manifest['entries'] as List? ?? const []))
        if (raw is Map && raw['id'] != null)
          raw['id'].toString(): raw.map(
            (key, value) => MapEntry(key.toString(), value),
          ),
    };

    final updated = <Note>[];
    final plans = <_MirrorPlan>[];
    var conflicts = 0;
    final nextEntries = <Map<String, Object?>>[];

    for (final note in notes.where(
      (item) => !item.isDeleted && !item.isVisual && !item.isTask,
    )) {
      final previous = entries[note.id];
      final fileName = previous?['file']?.toString() ?? _fileName(note);
      final file = _safeTarget(directory, fileName);
      final local = _documentText(note);
      final exists = await file.exists();
      final external =
          exists ? await file.readAsString(encoding: utf8) : local;

      late final ExternalMergeResult resolved;
      if (previous == null) {
        if (exists && external != local) {
          // Without a trusted merge base neither side may silently win.
          resolved = ExternalMergeResult(
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
        } else {
          resolved = ExternalMergeResult(
            exists
                ? ExternalChangeDecision.unchanged
                : ExternalChangeDecision.keepLocal,
            local,
          );
        }
      } else {
        final base = previous['base']?.toString();
        if (base == null) {
          throw const FormatException(
            'Manifest Markdown privo della base di merge.',
          );
        }
        resolved = ExternalChangeResolver.resolve(
          base: base,
          local: local,
          external: external,
        );
      }

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

      plans.add(
        _MirrorPlan(
          file: file,
          text: nextText,
          needsWrite: !exists || external != nextText,
        ),
      );
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
    if (utf8.encode(payload).length > maxManifestBytes) {
      throw const FormatException(
        'Il workspace è troppo grande per il manifest Markdown sicuro.',
      );
    }

    var written = 0;
    for (final plan in plans) {
      if (!plan.needsWrite) continue;
      await _atomicWrite(plan.file, plan.text);
      written++;
    }

    // A missing manifest with pre-existing files is intentionally not trusted.
    // Conflicts above preserve both sides before a new base can be finalized.
    if (!manifestExists && conflicts > 0) {
      // No-op marker: the returned payload becomes trusted only in finalize().
    }

    return MarkdownMirrorResult(
      updatedNotes: updated,
      writtenFiles: written,
      conflicts: conflicts,
      manifestPayload: payload,
    );
  }

  static Future<void> finalize(
    String directoryPath,
    MarkdownMirrorResult result,
  ) async {
    final directory = Directory(directoryPath);
    if (!await directory.exists()) {
      throw const FormatException('Cartella Markdown non accessibile.');
    }
    if (utf8.encode(result.manifestPayload).length > maxManifestBytes) {
      throw const FormatException('Manifest Markdown troppo grande.');
    }
    await _atomicWrite(
      File(p.join(directory.path, manifestName)),
      result.manifestPayload,
    );
  }

  static Future<Map<String, Object?>> _loadManifest(File file) async {
    if (!await file.exists()) {
      return const {'entries': <Object?>[]};
    }
    try {
      final text = await file.readAsString(encoding: utf8);
      if (utf8.encode(text).length > maxManifestBytes) {
        throw const FormatException('Manifest Markdown troppo grande.');
      }
      final decoded = jsonDecode(text);
      if (decoded is! Map ||
          decoded['format'] != 'notes-markdown-folder' ||
          decoded['version'] != manifestVersion ||
          decoded['entries'] is! List) {
        throw const FormatException('Manifest Markdown non valido.');
      }
      for (final raw in decoded['entries'] as List) {
        if (raw is! Map || raw['id'] == null || raw['file'] == null) {
          throw const FormatException('Voce manifest Markdown non valida.');
        }
        _validateFileName(raw['file'].toString());
        if (raw['base'] is! String) {
          throw const FormatException('Base manifest Markdown non valida.');
        }
      }
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Manifest Markdown non leggibile.');
    }
  }

  static File _safeTarget(Directory directory, String fileName) {
    _validateFileName(fileName);
    final root = p.normalize(p.absolute(directory.path));
    final target = p.normalize(p.absolute(p.join(root, fileName)));
    if (!p.isWithin(root, target)) {
      throw const FormatException('Percorso Markdown fuori dalla cartella.');
    }
    return File(target);
  }

  static void _validateFileName(String fileName) {
    if (fileName.isEmpty ||
        fileName != p.basename(fileName) ||
        fileName == manifestName ||
        fileName.contains('/') ||
        fileName.contains('\\') ||
        !fileName.toLowerCase().endsWith('.md')) {
      throw const FormatException('Nome file Markdown non sicuro.');
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
    final backup = File('${target.path}.bak');
    if (await temp.exists()) await temp.delete();
    await temp.writeAsString(text, encoding: utf8, flush: true);

    if (!await target.exists()) {
      await temp.rename(target.path);
      return;
    }

    // Atomic replace succeeds on platforms that support rename-over-existing.
    try {
      await temp.rename(target.path);
      return;
    } catch (_) {
      // Fall through to rollback-safe replacement.
    }

    if (await backup.exists()) await backup.delete();
    await target.rename(backup.path);
    try {
      await temp.rename(target.path);
      await backup.delete();
    } catch (_) {
      if (await target.exists()) await target.delete();
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
  }
}
