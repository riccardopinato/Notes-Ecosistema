import 'dart:convert';

enum DerivativeKind {
  transcript,
  cleanedTranscript,
  summary,
  extractedTasks,
}

class SourceDerivative {
  const SourceDerivative({
    required this.id,
    required this.sourceNoteId,
    required this.kind,
    required this.content,
    required this.sourceFingerprint,
    required this.createdAt,
    required this.engine,
    this.sourceAssetKey,
  });

  final String id;
  final String sourceNoteId;
  final String? sourceAssetKey;
  final DerivativeKind kind;
  final String content;
  final String sourceFingerprint;
  final int createdAt;
  final String engine;

  Map<String, Object?> toMap() => {
        'id': id,
        'sourceNoteId': sourceNoteId,
        'sourceAssetKey': sourceAssetKey,
        'kind': kind.name,
        'content': content,
        'sourceFingerprint': sourceFingerprint,
        'createdAt': createdAt,
        'engine': engine,
      };

  factory SourceDerivative.fromMap(Map<String, Object?> row) {
    final rawKind = row['kind']?.toString() ?? '';
    final kind = DerivativeKind.values.where((value) => value.name == rawKind);
    if (kind.isEmpty) {
      throw const FormatException('Tipo derivato non valido.');
    }
    return SourceDerivative(
      id: row['id']?.toString() ?? '',
      sourceNoteId: row['sourceNoteId']?.toString() ?? '',
      sourceAssetKey: row['sourceAssetKey']?.toString(),
      kind: kind.first,
      content: row['content']?.toString() ?? '',
      sourceFingerprint: row['sourceFingerprint']?.toString() ?? '',
      createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
      engine: row['engine']?.toString() ?? '',
    );
  }
}

abstract final class LocalDerivation {
  static String cleanTranscript(String input) {
    var text = input
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (text.isEmpty) return '';
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+|\n+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) {
      final first = value[0].toUpperCase();
      return '$first${value.substring(1)}';
    });
    text = sentences.join(' ');
    return text;
  }

  static String summarize(String input, {int maxSentences = 5}) {
    final cleaned = cleanTranscript(input);
    if (cleaned.isEmpty) return '';
    final sentences = cleaned
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
    if (sentences.length <= maxSentences) return sentences.join(' ');
    final scored = <({int index, String text, int score})>[];
    final frequencies = <String, int>{};
    for (final word in _words(cleaned)) {
      frequencies.update(word, (value) => value + 1, ifAbsent: () => 1);
    }
    for (var i = 0; i < sentences.length; i++) {
      final score = _words(sentences[i])
          .fold<int>(0, (sum, word) => sum + (frequencies[word] ?? 0));
      scored.add((index: i, text: sentences[i], score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final selected = scored.take(maxSentences).toList()
      ..sort((a, b) => a.index.compareTo(b.index));
    return selected.map((item) => item.text).join(' ');
  }

  static List<String> extractTasks(String input) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in input.split('\n')) {
      final line = raw.trim();
      if (line.isEmpty) continue;
      final checkbox =
          RegExp(r'^[-*]?\s*\[[ xX]\]\s+(.+)$').firstMatch(line);
      final action = RegExp(
        r'^(?:todo|task|azione|da fare|ricordati|ricordare)\s*[:\-]\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      final value = checkbox?.group(1) ?? action?.group(1);
      if (value == null) continue;
      final normalized = value.trim();
      if (normalized.isEmpty || !seen.add(normalized.toLowerCase())) continue;
      result.add(normalized);
      if (result.length >= 50) break;
    }
    return result;
  }

  static List<String> _words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((word) => word.length >= 3)
      .toList(growable: false);

  static String tasksAsMarkdown(List<String> tasks) =>
      tasks.map((task) => '- [ ] $task').join('\n');

  static String encodePayload(Object value) => jsonEncode(value);
}
