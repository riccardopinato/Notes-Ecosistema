import 'dart:convert';

class ResearchSource {
  const ResearchSource({
    required this.id,
    required this.noteId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    this.url,
    this.author,
    this.publishedAt,
    this.quote,
  });

  final String id;
  final String noteId;
  final String title;
  final String? url;
  final String? author;
  final String? publishedAt;
  final String? quote;
  final int createdAt;
  final int updatedAt;

  String get footnoteLabel {
    final compact = id.toLowerCase().replaceAll('-', '');
    final safe = compact.length >= 12 ? compact.substring(0, 12) : compact;
    return 'src-$safe';
  }

  String footnote() {
    final parts = <String>[
      if (author?.trim().isNotEmpty == true) author!.trim(),
      title.trim(),
      if (publishedAt?.trim().isNotEmpty == true) publishedAt!.trim(),
      if (url?.trim().isNotEmpty == true) url!.trim(),
    ];
    return '[^$footnoteLabel]: ${parts.join(' — ')}';
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'noteId': noteId,
        'title': title,
        'url': url,
        'author': author,
        'publishedAt': publishedAt,
        'quote': quote,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory ResearchSource.fromMap(Map<String, Object?> row) => ResearchSource(
        id: row['id']?.toString() ?? '',
        noteId: row['noteId']?.toString() ?? '',
        title: row['title']?.toString() ?? '',
        url: row['url']?.toString(),
        author: row['author']?.toString(),
        publishedAt: row['publishedAt']?.toString(),
        quote: row['quote']?.toString(),
        createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class NoteRelation {
  const NoteRelation({
    required this.id,
    required this.sourceId,
    required this.targetId,
    required this.label,
    required this.updatedAt,
  });

  final String id;
  final String sourceId;
  final String targetId;
  final String label;
  final int updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'sourceId': sourceId,
        'targetId': targetId,
        'label': label,
        'updatedAt': updatedAt,
      };

  factory NoteRelation.fromMap(Map<String, Object?> row) => NoteRelation(
        id: row['id']?.toString() ?? '',
        sourceId: row['sourceId']?.toString() ?? '',
        targetId: row['targetId']?.toString() ?? '',
        label: row['label']?.toString() ?? '',
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class RelationRollup {
  const RelationRollup({
    required this.total,
    required this.byLabel,
  });

  final int total;
  final Map<String, int> byLabel;

  factory RelationRollup.fromRelations(Iterable<NoteRelation> relations) {
    final counts = <String, int>{};
    var total = 0;
    for (final relation in relations) {
      total++;
      counts.update(relation.label, (value) => value + 1, ifAbsent: () => 1);
    }
    return RelationRollup(total: total, byLabel: counts);
  }
}

class SyncedBlock {
  const SyncedBlock({
    required this.id,
    required this.markdown,
    required this.updatedAt,
  });

  final String id;
  final String markdown;
  final int updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'markdown': markdown,
        'updatedAt': updatedAt,
      };

  factory SyncedBlock.fromMap(Map<String, Object?> row) => SyncedBlock(
        id: row['id']?.toString() ?? '',
        markdown: row['markdown']?.toString() ?? '',
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

abstract final class SyncedBlockCodec {
  static final marker = RegExp(r'\{\{notes-synced:([0-9a-fA-F-]{36})\}\}');

  static String reference(String id) {
    if (!RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(id)) {
      throw const FormatException('ID blocco sincronizzato non valido.');
    }
    return '{{notes-synced:${id.toLowerCase()}}}';
  }

  static String resolve(String markdown, Map<String, SyncedBlock> blocks) =>
      markdown.replaceAllMapped(marker, (match) {
        final id = match.group(1)!.toLowerCase();
        return blocks[id]?.markdown ?? match.group(0)!;
      });
}

abstract final class ResearchRules {
  static void validateSource(ResearchSource source) {
    if (source.id.trim().isEmpty ||
        source.noteId.trim().isEmpty ||
        source.title.trim().isEmpty ||
        source.title.length > 500) {
      throw const FormatException('Fonte di ricerca non valida.');
    }
    if (source.url != null) {
      final uri = Uri.tryParse(source.url!.trim());
      if (uri == null ||
          !uri.hasScheme ||
          !const {'http', 'https'}.contains(uri.scheme.toLowerCase())) {
        throw const FormatException('URL fonte non valido.');
      }
    }
    if ((source.quote?.length ?? 0) > 10000) {
      throw const FormatException('Citazione fonte troppo lunga.');
    }
  }

  static String encodeSources(List<ResearchSource> sources) =>
      jsonEncode(sources.map((source) => source.toMap()).toList());
}
