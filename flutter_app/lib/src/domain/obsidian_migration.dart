import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'attachments.dart';

class ObsidianDocument {
  const ObsidianDocument({
    required this.path,
    required this.title,
    required this.body,
    required this.tags,
    required this.frontMatterFields,
  });

  final String path;
  final String title;
  final String body;
  final List<String> tags;
  final List<String> frontMatterFields;
}

class ObsidianAsset {
  const ObsidianAsset({
    required this.path,
    required this.bytes,
    required this.type,
  });

  final String path;
  final Uint8List bytes;
  final AttachmentType type;
}

class ObsidianMigrationReport {
  const ObsidianMigrationReport({
    required this.documents,
    required this.assets,
    required this.unsupportedFiles,
    required this.unknownFrontMatterFields,
  });

  final int documents;
  final int assets;
  final List<String> unsupportedFiles;
  final Set<String> unknownFrontMatterFields;

  String userLabel() =>
      '$documents note · $assets allegati · '
      '${unsupportedFiles.length} file non supportati · '
      '${unknownFrontMatterFields.length} campi frontmatter extra';
}

class ObsidianVaultPackage {
  const ObsidianVaultPackage({
    required this.documents,
    required this.assets,
    required this.report,
    required this.sourceInstanceHint,
  });

  final List<ObsidianDocument> documents;
  final List<ObsidianAsset> assets;
  final ObsidianMigrationReport report;
  final String sourceInstanceHint;
}

abstract final class ObsidianMigration {
  static const maxZipBytes = 64 * 1024 * 1024;
  static const maxExpandedBytes = 192 * 1024 * 1024;
  static const maxDocuments = 10000;
  static const maxAssets = 1000;

  static ObsidianVaultPackage decode(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > maxZipBytes) {
      throw const FormatException('Vault ZIP non valido o troppo grande.');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final documents = <ObsidianDocument>[];
    final assets = <ObsidianAsset>[];
    final unsupported = <String>[];
    final unknownFields = <String>{};
    final identityPaths = <String>[];
    var expanded = 0;

    for (final entry in archive) {
      if (!entry.isFile) continue;
      final safePath = _safePath(entry.name);
      if (safePath == null) {
        throw const FormatException('Percorso non sicuro nel vault.');
      }
      final data = entry.readBytes();
      if (data == null) {
        throw const FormatException('File del vault non leggibile.');
      }
      expanded += data.length;
      if (expanded > maxExpandedBytes) {
        throw const FormatException('Vault espanso oltre il limite consentito.');
      }

      final ext = p.extension(safePath).toLowerCase();
      if (ext == '.md' || ext == '.markdown') {
        if (documents.length >= maxDocuments) {
          throw const FormatException('Troppi documenti Markdown nel vault.');
        }
        var text = utf8.decode(data, allowMalformed: false);
        if (text.startsWith('\uFEFF')) text = text.substring(1);
        final parsed = _parseFrontMatter(text);
        unknownFields.addAll(parsed.unknownFields);
        final title = parsed.title ??
            p.basenameWithoutExtension(safePath).trim().replaceAll('_', ' ');
        documents.add(
          ObsidianDocument(
            path: safePath,
            title: title.isEmpty ? 'Senza titolo' : title,
            body: parsed.body.trim(),
            tags: parsed.tags,
            frontMatterFields: parsed.fields,
          ),
        );
        identityPaths.add(safePath.toLowerCase());
        continue;
      }

      final type = Attachments.typeFromName(safePath);
      if (type != null) {
        if (assets.length >= maxAssets) {
          unsupported.add(safePath);
          continue;
        }
        if (data.isEmpty || data.length > Attachments.fileLimit) {
          unsupported.add(safePath);
          continue;
        }
        assets.add(
          ObsidianAsset(
            path: safePath,
            bytes: Uint8List.fromList(data),
            type: type,
          ),
        );
        continue;
      }

      if (!safePath.startsWith('.obsidian/')) unsupported.add(safePath);
    }

    identityPaths.sort();
    final sourceHint = sha256
        .convert(utf8.encode(identityPaths.take(128).join('\n')))
        .toString()
        .substring(0, 24);
    return ObsidianVaultPackage(
      documents: documents,
      assets: assets,
      sourceInstanceHint: sourceHint,
      report: ObsidianMigrationReport(
        documents: documents.length,
        assets: assets.length,
        unsupportedFiles: unsupported,
        unknownFrontMatterFields: unknownFields,
      ),
    );
  }

  static String resolveBody({
    required ObsidianDocument document,
    required Map<String, String> noteIdsByKey,
    required Map<String, String> assetKeysByPath,
  }) {
    var body = document.body;

    body = body.replaceAllMapped(
      RegExp(r'!\[\[([^\]|#]+)(?:#[^\]]+)?(?:\|[^\]]+)?\]\]'),
      (match) {
        final raw = match.group(1)!.trim();
        final key = _assetLookup(raw, document.path, assetKeysByPath);
        if (key == null) return match.group(0)!;
        return '![${p.basename(raw)}](notes-asset://$key)';
      },
    );

    body = body.replaceAllMapped(
      RegExp(r'\[\[([^\]|#]+)(?:#[^\]|]+)?(?:\|([^\]]+))?\]\]'),
      (match) {
        final target = match.group(1)!.trim();
        final label = match.group(2)?.trim();
        final noteId = _noteLookup(target, document.path, noteIdsByKey);
        if (noteId == null) return match.group(0)!;
        return '[${label?.isNotEmpty == true ? label : target}]'
            '(notes://object/$noteId)';
      },
    );

    body = body.replaceAllMapped(
      RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
      (match) {
        final raw = Uri.decodeComponent(match.group(2)!.trim());
        if (raw.startsWith('http://') ||
            raw.startsWith('https://') ||
            raw.startsWith('notes-asset://')) {
          return match.group(0)!;
        }
        final key = _assetLookup(raw, document.path, assetKeysByPath);
        if (key == null) return match.group(0)!;
        final label = match.group(1)!.trim();
        return '![${label.isEmpty ? p.basename(raw) : label}]'
            '(notes-asset://$key)';
      },
    );

    if (document.path.contains('/')) {
      body = '<!-- obsidian_path: ${document.path} -->\n\n$body';
    }
    return body.trim();
  }

  static Map<String, String> noteLookup(
    Iterable<({String path, String title, String id})> values,
  ) {
    final result = <String, String>{};
    for (final value in values) {
      final path = _normalizePath(value.path);
      result[path] = value.id;
      result[p.withoutExtension(path)] = value.id;
      final title = value.title.trim().toLowerCase();
      if (title.isNotEmpty) result.putIfAbsent(title, () => value.id);
      final base = p.basenameWithoutExtension(path).toLowerCase();
      if (base.isNotEmpty) result.putIfAbsent(base, () => value.id);
    }
    return result;
  }

  static Map<String, String> assetLookup(
    Iterable<({String path, String key})> values,
  ) {
    final result = <String, String>{};
    for (final value in values) {
      result[_normalizePath(value.path)] = value.key;
      result.putIfAbsent(
        p.basename(value.path).toLowerCase(),
        () => value.key,
      );
    }
    return result;
  }

  static String? _noteLookup(
    String raw,
    String sourcePath,
    Map<String, String> values,
  ) {
    final normalized = _normalizePath(raw);
    final relative = _normalizePath(
      p.join(p.dirname(sourcePath), raw),
    );
    return values[relative] ??
        values[normalized] ??
        values[p.withoutExtension(normalized)] ??
        values[p.basenameWithoutExtension(normalized).toLowerCase()];
  }

  static String? _assetLookup(
    String raw,
    String sourcePath,
    Map<String, String> values,
  ) {
    final normalized = _normalizePath(raw);
    final relative = _normalizePath(
      p.join(p.dirname(sourcePath), raw),
    );
    return values[relative] ??
        values[normalized] ??
        values[p.basename(normalized).toLowerCase()];
  }

  static String _normalizePath(String value) => p
      .normalize(value.replaceAll('\\', '/'))
      .replaceAll('\\', '/')
      .replaceFirst(RegExp(r'^\./'), '')
      .toLowerCase();

  static String? _safePath(String raw) {
    final normalized = p
        .normalize(raw.replaceAll('\\', '/'))
        .replaceAll('\\', '/')
        .replaceFirst(RegExp(r'^\./'), '');
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        normalized == '..' ||
        normalized.startsWith('../') ||
        normalized.contains('/../')) {
      return null;
    }
    return normalized;
  }

  static ({
    String body,
    String? title,
    List<String> tags,
    List<String> fields,
    Set<String> unknownFields,
  }) _parseFrontMatter(String text) {
    if (!text.startsWith('---\n')) {
      return (
        body: text,
        title: null,
        tags: const [],
        fields: const [],
        unknownFields: const {},
      );
    }
    final end = text.indexOf('\n---\n', 4);
    if (end < 0 || end > 20000) {
      return (
        body: text,
        title: null,
        tags: const [],
        fields: const [],
        unknownFields: const {},
      );
    }
    final header = text.substring(4, end);
    final fields = <String>[];
    final unknown = <String>{};
    String? title;
    final tags = <String>{};
    String? activeList;

    for (final rawLine in const LineSplitter().convert(header)) {
      final line = rawLine.trimRight();
      if (line.trim().startsWith('- ') && activeList == 'tags') {
        final value = line.trim().substring(2).trim();
        if (value.isNotEmpty) tags.add(_cleanYaml(value));
        continue;
      }
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      fields.add(key);
      activeList = key.toLowerCase();
      switch (activeList) {
        case 'title':
          title = _cleanYaml(value);
          break;
        case 'tags':
          if (value.startsWith('[') && value.endsWith(']')) {
            for (final item in value.substring(1, value.length - 1).split(',')) {
              final clean = _cleanYaml(item.trim());
              if (clean.isNotEmpty) tags.add(clean);
            }
          } else if (value.isNotEmpty) {
            for (final item in value.split(',')) {
              final clean = _cleanYaml(item.trim());
              if (clean.isNotEmpty) tags.add(clean);
            }
          }
          break;
        case 'aliases':
        case 'cssclasses':
          break;
        default:
          unknown.add(key);
      }
    }

    return (
      body: text.substring(end + 5),
      title: title?.trim().isEmpty == true ? null : title?.trim(),
      tags: tags.toList(growable: false),
      fields: fields,
      unknownFields: unknown,
    );
  }

  static String _cleanYaml(String value) {
    final clean = value.trim();
    if (clean.length >= 2 &&
        ((clean.startsWith('"') && clean.endsWith('"')) ||
            (clean.startsWith("'") && clean.endsWith("'")))) {
      return clean.substring(1, clean.length - 1).trim();
    }
    return clean;
  }
}
