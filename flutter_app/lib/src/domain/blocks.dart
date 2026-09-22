import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'attachments.dart';

enum ContentBlockType {
  markdown,
  text,
  heading,
  checklist,
  task,
  image,
  audio,
  file,
  drawing,
  whiteboard,
  bookmark,
  table,
  code,
  quote,
  callout,
  divider,
}

extension ContentBlockTypeWire on ContentBlockType {
  String get wire => name.toUpperCase();

  static ContentBlockType parse(String raw) {
    final value = raw.toLowerCase();
    return ContentBlockType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => ContentBlockType.markdown,
    );
  }
}

class ContentBlock {
  const ContentBlock({
    required this.id,
    required this.ownerId,
    required this.position,
    required this.type,
    required this.createdAt,
    required this.updatedAt,
    this.ownerType = 'note',
    this.parentBlockId,
    this.text = '',
    this.checked,
    this.metadataJson = '{}',
  });

  final String id;
  final String ownerId;
  final String ownerType;
  final String? parentBlockId;
  final int position;
  final ContentBlockType type;
  final String text;
  final bool? checked;
  final String metadataJson;
  final int createdAt;
  final int updatedAt;

  factory ContentBlock.fromMap(Map<String, Object?> row) => ContentBlock(
        id: row['id']?.toString() ?? '',
        ownerId: row['ownerId']?.toString() ?? '',
        ownerType: row['ownerType']?.toString() ?? 'note',
        parentBlockId: row['parentBlockId']?.toString(),
        position: (row['position'] as num?)?.toInt() ?? 0,
        type: ContentBlockTypeWire.parse(row['type']?.toString() ?? 'MARKDOWN'),
        text: row['text']?.toString() ?? '',
        checked: row['checked'] == null
            ? null
            : (row['checked'] as num?)?.toInt() == 1,
        metadataJson: row['metadataJson']?.toString() ?? '{}',
        createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'ownerId': ownerId,
        'ownerType': ownerType,
        'parentBlockId': parentBlockId,
        'position': position,
        'type': type.wire,
        'text': text,
        'checked': checked == null ? null : (checked! ? 1 : 0),
        'metadataJson': metadataJson,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  ContentBlock copyWith({
    String? id,
    String? ownerId,
    String? ownerType,
    Object? parentBlockId = _unset,
    int? position,
    ContentBlockType? type,
    String? text,
    Object? checked = _unset,
    String? metadataJson,
    int? createdAt,
    int? updatedAt,
  }) =>
      ContentBlock(
        id: id ?? this.id,
        ownerId: ownerId ?? this.ownerId,
        ownerType: ownerType ?? this.ownerType,
        parentBlockId: identical(parentBlockId, _unset)
            ? this.parentBlockId
            : parentBlockId as String?,
        position: position ?? this.position,
        type: type ?? this.type,
        text: text ?? this.text,
        checked:
            identical(checked, _unset) ? this.checked : checked as bool?,
        metadataJson: metadataJson ?? this.metadataJson,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

const _unset = Object();

abstract final class ContentBlocks {
  static const maxBlocksPerOwner = 2000;
  static const maxTextBytes = 512 * 1024;
  static const maxMetadataBytes = 128 * 1024;

  static void validate(ContentBlock block) {
    if (block.id.trim().isEmpty) {
      throw const FormatException('ID blocco mancante.');
    }
    if (block.ownerId.trim().isEmpty || block.ownerType.trim().isEmpty) {
      throw const FormatException('Contenitore blocco mancante.');
    }
    if (block.position < 0) {
      throw const FormatException('Posizione blocco non valida.');
    }
    if (utf8.encode(block.text).length > maxTextBytes) {
      throw const FormatException('Il contenuto del blocco è troppo grande.');
    }
    if (utf8.encode(block.metadataJson).length > maxMetadataBytes) {
      throw const FormatException('I metadati del blocco sono troppo grandi.');
    }
    if (block.parentBlockId == block.id) {
      throw const FormatException('Un blocco non può contenere sé stesso.');
    }
    if (block.type != ContentBlockType.checklist &&
        block.type != ContentBlockType.task &&
        block.checked != null) {
      throw const FormatException(
        'Lo stato completato è valido solo per checklist e attività.',
      );
    }
  }

  static List<ContentBlock> normalize(
    String ownerId,
    List<ContentBlock> blocks, {
    String ownerType = 'note',
    int? now,
  }) {
    if (blocks.length > maxBlocksPerOwner) {
      throw const FormatException(
        'Troppi blocchi nello stesso contenitore.',
      );
    }
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final ids = <String>{};
    return [
      for (var index = 0; index < blocks.length; index++)
        () {
          final source = blocks[index];
          final id = source.id.trim().isEmpty
              ? const Uuid().v4()
              : source.id;
          if (!ids.add(id)) {
            throw FormatException('ID blocco duplicato: $id');
          }
          final normalized = source.copyWith(
            id: id,
            ownerId: ownerId,
            ownerType: ownerType,
            position: index,
            createdAt:
                source.createdAt > 0 ? source.createdAt : timestamp,
            updatedAt: timestamp,
          );
          validate(normalized);
          return normalized;
        }(),
    ];
  }
}

abstract final class BlockEditorCodec {
  static final _checklist =
      RegExp(r'^\s*- \[([ xX])\]\s*(.*)$');
  static final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
  static final _divider =
      RegExp(r'^\s*(---|\*\*\*|___)\s*$');
  static final _attachmentOnly = RegExp(
    r'^\s*\[[^\]]+\]\(notes-asset://[^)]+\)\s*$',
  );
  static final _sketchLink = RegExp(
    r'^\s*\[Sketch: ([^\]]*)\]\(notes-sketch://([A-Za-z0-9-]+)\)\s*$',
  );
  static final _whiteboardLink = RegExp(
    r'^\s*\[Whiteboard: ([^\]]*)\]\(notes-board://([A-Za-z0-9-]+)\)\s*$',
  );

  static List<ContentBlock> parse(
    String noteId,
    String markdown, {
    int? now,
  }) {
    if (noteId.trim().isEmpty) {
      throw const FormatException('Nota mancante.');
    }
    if (markdown.isEmpty) return const [];

    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    final normalized =
        markdown.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final result = <ContentBlock>[];
    final paragraph = <String>[];
    var index = 0;
    final grave = String.fromCharCode(0x60);

    void add(
      ContentBlockType type, {
      String text = '',
      bool? checked,
      String metadata = '{}',
    }) {
      result.add(
        ContentBlock(
          id: const Uuid().v4(),
          ownerId: noteId,
          position: result.length,
          type: type,
          text: text,
          checked: checked,
          metadataJson: metadata,
          createdAt: timestamp,
          updatedAt: timestamp,
        ),
      );
    }

    void flushParagraph() {
      if (paragraph.isEmpty) return;
      final text = paragraph.join('\n');
      add(
        _looksLikeRichMarkdown(text)
            ? ContentBlockType.markdown
            : ContentBlockType.text,
        text: text,
      );
      paragraph.clear();
    }

    while (index < lines.length) {
      final line = lines[index];

      if (line.startsWith(grave * 3)) {
        flushParagraph();
        final fenceLength =
            line.codeUnits.takeWhile((c) => c == 0x60).length;
        final fence = List<String>.filled(fenceLength, grave).join();
        final language = line.substring(fenceLength).trim();
        index++;
        final code = <String>[];
        while (index < lines.length &&
            !lines[index].startsWith(fence)) {
          code.add(lines[index]);
          index++;
        }
        if (index < lines.length) index++;
        add(
          ContentBlockType.code,
          text: code.join('\n'),
          metadata: _metadata('language', language),
        );
        continue;
      }

      if (line.trim().isEmpty) {
        flushParagraph();
        index++;
        continue;
      }

      final heading = _heading.firstMatch(line);
      if (heading != null) {
        flushParagraph();
        add(
          ContentBlockType.heading,
          text: heading.group(2) ?? '',
          metadata: _metadata(
            'level',
            (heading.group(1)?.length ?? 2).clamp(1, 3).toString(),
          ),
        );
        index++;
        continue;
      }

      final task = _checklist.firstMatch(line);
      if (task != null) {
        flushParagraph();
        add(
          ContentBlockType.checklist,
          text: task.group(2) ?? '',
          checked: (task.group(1) ?? '').toLowerCase() == 'x',
        );
        index++;
        continue;
      }

      if (_divider.hasMatch(line)) {
        flushParagraph();
        add(ContentBlockType.divider);
        index++;
        continue;
      }

      if (line.startsWith('> ') || line == '>') {
        flushParagraph();
        final quote = <String>[];
        while (index < lines.length &&
            (lines[index].startsWith('> ') || lines[index] == '>')) {
          quote.add(
            lines[index].startsWith('> ')
                ? lines[index].substring(2)
                : '',
          );
          index++;
        }
        add(ContentBlockType.quote, text: quote.join('\n'));
        continue;
      }

      if (_attachmentOnly.hasMatch(line)) {
        flushParagraph();
        final refs = Attachments.refs(line);
        final ref = refs.isEmpty ? null : refs.first;
        add(
          switch (ref?.type.category) {
            AttachmentCategory.image => ContentBlockType.image,
            AttachmentCategory.audio => ContentBlockType.audio,
            _ => ContentBlockType.file,
          },
          text: line,
        );
        index++;
        continue;
      }

      final sketch = _sketchLink.firstMatch(line);
      if (sketch != null) {
        flushParagraph();
        add(
          ContentBlockType.drawing,
          text: (sketch.group(1) ?? '').trim().isEmpty
              ? 'Disegno'
              : sketch.group(1)!,
          metadata: drawingMetadata(sketch.group(2)!),
        );
        index++;
        continue;
      }

      final whiteboard = _whiteboardLink.firstMatch(line);
      if (whiteboard != null) {
        flushParagraph();
        add(
          ContentBlockType.whiteboard,
          text: (whiteboard.group(1) ?? '').trim().isEmpty
              ? 'Lavagna'
              : whiteboard.group(1)!,
          metadata: whiteboardMetadata(whiteboard.group(2)!),
        );
        index++;
        continue;
      }

      paragraph.add(line);
      index++;
    }

    flushParagraph();
    return canonicalize(noteId, result, now: timestamp);
  }

  static String toMarkdown(List<ContentBlock> blocks) {
    final sorted = [...blocks]..sort((a, b) => a.position.compareTo(b.position));
    final parts = <String>[];
    final grave = String.fromCharCode(0x60);

    for (final block in sorted) {
      String? value;
      switch (block.type) {
        case ContentBlockType.text:
        case ContentBlockType.markdown:
          value = block.text;
          break;
        case ContentBlockType.heading:
          final level = headingLevel(block);
          value = block.text.trim().isEmpty
              ? '#' * level
              : '${'#' * level} ${block.text}';
          break;
        case ContentBlockType.checklist:
        case ContentBlockType.task:
          value =
              '- [${block.checked == true ? 'x' : ' '}] ${block.text}';
          break;
        case ContentBlockType.quote:
          value = block.text
              .split('\n')
              .map((line) => '> $line')
              .join('\n');
          break;
        case ContentBlockType.code:
          final language =
              metadataValue(block.metadataJson, 'language') ?? '';
          var longest = 0;
          for (final match in RegExp(r'\x60+').allMatches(block.text)) {
            longest = longest < match.group(0)!.length
                ? match.group(0)!.length
                : longest;
          }
          final fence = List<String>.filled(
            (longest + 1).clamp(3, 1000).toInt(),
            grave,
          ).join();
          value = '$fence$language\n${block.text}\n$fence';
          break;
        case ContentBlockType.callout:
          value = block.text.trim().isEmpty
              ? '>'
              : block.text.split('\n').map((e) => '> $e').join('\n');
          break;
        case ContentBlockType.divider:
          value = '---';
          break;
        case ContentBlockType.drawing:
          final id = sketchId(block);
          value = id == null
              ? (block.text.contains('notes-sketch://')
                  ? block.text
                  : '')
              : '[Sketch: ${block.text.trim().isEmpty ? 'Disegno' : block.text}](notes-sketch://$id)';
          break;
        case ContentBlockType.whiteboard:
          final id = whiteboardId(block);
          value = id == null
              ? (block.text.contains('notes-board://')
                  ? block.text
                  : '')
              : '[Whiteboard: ${block.text.trim().isEmpty ? 'Lavagna' : block.text}](notes-board://$id)';
          break;
        case ContentBlockType.image:
        case ContentBlockType.audio:
        case ContentBlockType.file:
        case ContentBlockType.bookmark:
        case ContentBlockType.table:
          value = block.text.trim().isEmpty ? null : block.text;
          break;
      }
      if (value != null) parts.add(value);
    }
    return parts.join('\n\n').trimRight();
  }

  static List<ContentBlock> canonicalize(
    String noteId,
    List<ContentBlock> blocks, {
    int? now,
  }) =>
      ContentBlocks.normalize(noteId, blocks, now: now);

  static ContentBlock newBlock(
    String noteId,
    ContentBlockType type,
    int position, {
    String text = '',
    int? now,
  }) {
    final timestamp = now ?? DateTime.now().millisecondsSinceEpoch;
    return ContentBlock(
      id: const Uuid().v4(),
      ownerId: noteId,
      position: position,
      type: type,
      text: text,
      checked: type == ContentBlockType.checklist ||
              type == ContentBlockType.task
          ? false
          : null,
      metadataJson:
          type == ContentBlockType.heading ? _metadata('level', '2') : '{}',
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static ContentBlock changeType(
    ContentBlock block,
    ContentBlockType type,
  ) {
    var metadata = block.metadataJson;
    if (type == ContentBlockType.heading &&
        metadataValue(metadata, 'level') == null) {
      metadata = _metadata('level', '2');
    } else if (block.type == ContentBlockType.heading &&
        type != ContentBlockType.heading) {
      metadata = '{}';
    }
    return block.copyWith(
      type: type,
      checked: type == ContentBlockType.checklist ||
              type == ContentBlockType.task
          ? block.checked ?? false
          : null,
      metadataJson: metadata,
    );
  }

  static ContentBlock withHeadingLevel(
    ContentBlock block,
    int level,
  ) =>
      block.copyWith(
        type: ContentBlockType.heading,
        checked: null,
        metadataJson:
            _metadata('level', level.clamp(1, 3).toString()),
      );

  static int headingLevel(ContentBlock block) =>
      int.tryParse(metadataValue(block.metadataJson, 'level') ?? '2')
          ?.clamp(1, 3)
          .toInt() ??
      2;

  static String? sketchId(ContentBlock block) =>
      block.type == ContentBlockType.drawing
          ? metadataValue(block.metadataJson, 'sketchId')
          : null;

  static String? whiteboardId(ContentBlock block) =>
      block.type == ContentBlockType.whiteboard
          ? metadataValue(block.metadataJson, 'whiteboardId')
          : null;

  static String drawingMetadata(String sketchId) =>
      _metadata('sketchId', sketchId);

  static String whiteboardMetadata(String whiteboardId) =>
      _metadata('whiteboardId', whiteboardId);

  static bool _looksLikeRichMarkdown(String text) =>
      text.contains('[[') ||
      text.contains('**') ||
      text.contains('__') ||
      text.contains('](') ||
      RegExp(r'(^|\n)\s*[-*+]\s+').hasMatch(text) ||
      RegExp(r'(^|\n)\s*\d+\.\s+').hasMatch(text) ||
      RegExp(r'\[[^]]+\]\([^)]+\)').hasMatch(text);

  static String _metadata(String key, String value) =>
      jsonEncode({key: value});

  static String? metadataValue(String raw, String key) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded[key] != null) {
        return decoded[key].toString();
      }
    } catch (_) {}
    return null;
  }
}
