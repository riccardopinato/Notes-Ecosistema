import 'dart:convert';

enum AdaptiveEditorLevel { full, reduced, minimal }

class AdaptiveEditorProfile {
  const AdaptiveEditorProfile({
    required this.level,
    required this.bytes,
    required this.lines,
    required this.draftDebounce,
    required this.liveBlockParsing,
    required this.liveKnowledgeRefresh,
  });

  final AdaptiveEditorLevel level;
  final int bytes;
  final int lines;
  final Duration draftDebounce;
  final bool liveBlockParsing;
  final bool liveKnowledgeRefresh;

  bool get degraded => level != AdaptiveEditorLevel.full;

  String get label => switch (level) {
        AdaptiveEditorLevel.full => 'Completo',
        AdaptiveEditorLevel.reduced => 'Leggero',
        AdaptiveEditorLevel.minimal => 'Essenziale',
      };
}

abstract final class AdaptiveEditorPolicy {
  static const reducedBytes = 64 * 1024;
  static const minimalBytes = 192 * 1024;
  static const reducedLines = 600;
  static const minimalLines = 1800;

  static AdaptiveEditorProfile evaluate(String text) {
    final bytes = utf8.encode(text).length;
    final lines = text.isEmpty ? 0 : '\n'.allMatches(text).length + 1;

    final level = bytes >= minimalBytes || lines >= minimalLines
        ? AdaptiveEditorLevel.minimal
        : bytes >= reducedBytes || lines >= reducedLines
            ? AdaptiveEditorLevel.reduced
            : AdaptiveEditorLevel.full;

    return switch (level) {
      AdaptiveEditorLevel.full => AdaptiveEditorProfile(
          level: level,
          bytes: bytes,
          lines: lines,
          draftDebounce: const Duration(milliseconds: 280),
          liveBlockParsing: true,
          liveKnowledgeRefresh: true,
        ),
      AdaptiveEditorLevel.reduced => AdaptiveEditorProfile(
          level: level,
          bytes: bytes,
          lines: lines,
          draftDebounce: const Duration(milliseconds: 650),
          liveBlockParsing: false,
          liveKnowledgeRefresh: false,
        ),
      AdaptiveEditorLevel.minimal => AdaptiveEditorProfile(
          level: level,
          bytes: bytes,
          lines: lines,
          draftDebounce: const Duration(milliseconds: 1200),
          liveBlockParsing: false,
          liveKnowledgeRefresh: false,
        ),
    };
  }
}
