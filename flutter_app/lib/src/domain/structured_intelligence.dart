import 'dart:convert';

import 'local_llm.dart';

enum StructuredCommandKind {
  createTask,
  addTags,
  setPriority,
  checklistItem,
}

enum StructuredAnalysisSource {
  geminiNano,
  needle,
  deterministic,
}

class StructuredCommand {
  const StructuredCommand({
    required this.kind,
    required this.confidence,
    this.title,
    this.tags = const [],
    this.priority,
    this.dueText,
    this.evidence,
  });

  final StructuredCommandKind kind;
  final double confidence;
  final String? title;
  final List<String> tags;
  final String? priority;
  final String? dueText;
  final String? evidence;

  Map<String, Object?> toJson() => {
        'kind': switch (kind) {
          StructuredCommandKind.createTask => 'create_task',
          StructuredCommandKind.addTags => 'add_tags',
          StructuredCommandKind.setPriority => 'set_priority',
          StructuredCommandKind.checklistItem => 'checklist_item',
        },
        'confidence': confidence,
        if (title != null) 'title': title,
        if (tags.isNotEmpty) 'tags': tags,
        if (priority != null) 'priority': priority,
        if (dueText != null) 'dueText': dueText,
        if (evidence != null) 'evidence': evidence,
      };
}

class StructuredAnalysis {
  const StructuredAnalysis({
    required this.commands,
    required this.source,
    this.modelName,
  });

  final List<StructuredCommand> commands;
  final StructuredAnalysisSource source;
  final String? modelName;

  bool get empty => commands.isEmpty;
}

abstract final class StructuredIntelligencePolicy {
  static const maxBodyChars = 12000;
  static const maxCommands = 12;
  static const maxTitleChars = 240;
  static const maxEvidenceChars = 320;
  static const maxTags = 12;

  static String notePrompt({
    required String title,
    required String body,
  }) {
    final safeTitle = _trim(title, 500);
    final safeBody = _trim(body, maxBodyChars);
    return '''
Analizza la nota seguente e restituisci SOLO JSON valido, senza markdown.

FORMATO:
{
  "commands": [
    {
      "kind": "create_task | add_tags | set_priority | checklist_item",
      "title": "testo breve opzionale",
      "tags": ["tag1", "tag2"],
      "priority": "low | medium | high",
      "dueText": "scadenza testuale opzionale",
      "confidence": 0.0,
      "evidence": "frase sorgente breve"
    }
  ]
}

REGOLE:
- massimo $maxCommands comandi;
- non inventare task, tag, priorità o scadenze non supportati dal testo;
- usa create_task solo per azioni realmente richieste o chiaramente implicate;
- usa checklist_item per elementi esplicitamente presentati come checklist;
- usa add_tags solo per concetti centrali della nota;
- usa set_priority solo se la priorità è esplicita;
- confidence deve essere tra 0 e 1;
- non proporre eliminazioni, invii, acquisti o altre azioni distruttive/esterne;
- se non c'è nulla di utile restituisci {"commands":[]}.

TITOLO
$safeTitle

NOTA
$safeBody
'''
        .trim();
  }

  static StructuredAnalysis parseGemini(
    String raw, {
    String? modelName = LocalLlmPolicy.preferredModel,
  }) =>
      parseLocalJson(
        raw,
        source: StructuredAnalysisSource.geminiNano,
        modelName: modelName,
      );

  static StructuredAnalysis parseNeedle(
    String raw, {
    String? modelName = needle20LModelName,
  }) =>
      parseLocalJson(
        raw,
        source: StructuredAnalysisSource.needle,
        modelName: modelName,
      );

  static const needle20LModelName = 'Needle 3 20L';

  static StructuredAnalysis parseLocalJson(
    String raw, {
    required StructuredAnalysisSource source,
    String? modelName,
  }) {
    final decoded = _decodeObject(raw);
    final commandsRaw = decoded['commands'];
    if (commandsRaw is! List) {
      return StructuredAnalysis(
        commands: const [],
        source: source,
        modelName: modelName,
      );
    }

    final commands = <StructuredCommand>[];
    for (final item in commandsRaw.take(maxCommands)) {
      if (item is! Map) continue;
      final command = _parseCommand(item);
      if (command != null) commands.add(command);
    }

    return StructuredAnalysis(
      commands: commands,
      source: source,
      modelName: modelName,
    );
  }

  static StructuredAnalysis deterministic({
    required String body,
  }) {
    final commands = <StructuredCommand>[];
    final lines = body.replaceAll('\r\n', '\n').split('\n');

    for (final rawLine in lines) {
      if (commands.length >= maxCommands) break;
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final taskMatch = RegExp(r'^[-*]\s*\[\s\]\s+(.+)$').firstMatch(line);
      if (taskMatch != null) {
        final title = _cleanText(taskMatch.group(1), maxTitleChars);
        if (title != null) {
          commands.add(
            StructuredCommand(
              kind: StructuredCommandKind.createTask,
              title: title,
              confidence: 1,
              evidence: _cleanText(line, maxEvidenceChars),
            ),
          );
        }
        continue;
      }

      final checklistMatch =
          RegExp(r'^(?:[-*]|\d+[.)])\s+(.+)$').firstMatch(line);
      if (checklistMatch != null) {
        final title = _cleanText(checklistMatch.group(1), maxTitleChars);
        if (title != null) {
          commands.add(
            StructuredCommand(
              kind: StructuredCommandKind.checklistItem,
              title: title,
              confidence: 0.92,
              evidence: _cleanText(line, maxEvidenceChars),
            ),
          );
        }
      }
    }

    final tags = RegExp(r'(?<!\w)#([\p{L}\p{N}_-]{2,40})', unicode: true)
        .allMatches(body)
        .map((match) => match.group(1)?.toLowerCase())
        .whereType<String>()
        .toSet()
        .take(maxTags)
        .toList(growable: false);

    if (tags.isNotEmpty && commands.length < maxCommands) {
      commands.add(
        StructuredCommand(
          kind: StructuredCommandKind.addTags,
          tags: tags,
          confidence: 1,
          evidence: tags.map((tag) => '#$tag').join(' '),
        ),
      );
    }

    return StructuredAnalysis(
      commands: commands.take(maxCommands).toList(growable: false),
      source: StructuredAnalysisSource.deterministic,
    );
  }

  static Map<String, Object?> _decodeObject(String raw) {
    var candidate = raw.trim();
    if (candidate.startsWith('~~~') || candidate.startsWith('```')) {
      candidate = candidate
          .replaceFirst(RegExp(r'^(?:~~~|```)(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*(?:~~~|```)\s*$'), '');
    }

    try {
      final decoded = jsonDecode(candidate);
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      final first = candidate.indexOf('{');
      final last = candidate.lastIndexOf('}');
      if (first >= 0 && last > first) {
        final decoded = jsonDecode(candidate.substring(first, last + 1));
        if (decoded is Map) {
          return decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        }
      }
    }
    return const {};
  }

  static StructuredCommand? _parseCommand(Map raw) {
    final kind = switch (raw['kind']?.toString().trim().toLowerCase()) {
      'create_task' => StructuredCommandKind.createTask,
      'add_tags' => StructuredCommandKind.addTags,
      'set_priority' => StructuredCommandKind.setPriority,
      'checklist_item' => StructuredCommandKind.checklistItem,
      _ => null,
    };
    if (kind == null) return null;

    final confidence = _confidence(raw['confidence']);
    final title = _cleanText(raw['title'], maxTitleChars);
    final evidence = _cleanText(raw['evidence'], maxEvidenceChars);
    final dueText = _cleanText(raw['dueText'], 120);
    final priority = switch (raw['priority']?.toString().toLowerCase()) {
      'low' => 'low',
      'medium' => 'medium',
      'high' => 'high',
      _ => null,
    };
    final tags = raw['tags'] is List
        ? (raw['tags'] as List)
            .map((value) => _cleanTag(value))
            .whereType<String>()
            .toSet()
            .take(maxTags)
            .toList(growable: false)
        : const <String>[];

    switch (kind) {
      case StructuredCommandKind.createTask:
      case StructuredCommandKind.checklistItem:
        if (title == null) return null;
        break;
      case StructuredCommandKind.addTags:
        if (tags.isEmpty) return null;
        break;
      case StructuredCommandKind.setPriority:
        if (priority == null) return null;
        break;
    }

    return StructuredCommand(
      kind: kind,
      title: title,
      tags: tags,
      priority: priority,
      dueText: dueText,
      confidence: confidence,
      evidence: evidence,
    );
  }

  static double _confidence(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    return (parsed ?? 0.5).clamp(0, 1).toDouble();
  }

  static String? _cleanTag(Object? value) {
    final tag = value?.toString().trim().replaceFirst(RegExp(r'^#+'), '');
    if (tag == null || tag.length < 2 || tag.length > 40) return null;
    if (!RegExp(r'^[\p{L}\p{N}_-]+$', unicode: true).hasMatch(tag)) return null;
    return tag.toLowerCase();
  }

  static String? _cleanText(Object? value, int maxChars) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) return null;
    return _trim(text, maxChars);
  }

  static String _trim(String value, int maxChars) {
    final normalized = value.trim();
    if (normalized.length <= maxChars) return normalized;
    return normalized.substring(0, maxChars);
  }
}
