class LocalLlmStatus {
  const LocalLlmStatus({
    required this.supported,
    required this.installed,
    required this.loaded,
    required this.runtime,
    required this.backend,
    required this.modelName,
    required this.modelBytes,
    required this.memoryClassMb,
    required this.processors,
    this.error,
  });

  final bool supported;
  final bool installed;
  final bool loaded;
  final String runtime;
  final String backend;
  final String? modelName;
  final int modelBytes;
  final int memoryClassMb;
  final int processors;
  final String? error;

  factory LocalLlmStatus.fromMap(Map<Object?, Object?> raw) => LocalLlmStatus(
        supported: raw['supported'] == true,
        installed: raw['installed'] == true,
        loaded: raw['loaded'] == true,
        runtime: raw['runtime']?.toString() ?? 'LiteRT-LM',
        backend: raw['backend']?.toString() ?? 'CPU',
        modelName: raw['modelName']?.toString(),
        modelBytes: (raw['modelBytes'] as num?)?.toInt() ?? 0,
        memoryClassMb: (raw['memoryClassMb'] as num?)?.toInt() ?? 0,
        processors: (raw['processors'] as num?)?.toInt() ?? 0,
        error: raw['error']?.toString(),
      );
}

class LocalLlmGeneration {
  const LocalLlmGeneration({
    required this.text,
    required this.elapsedMs,
    required this.modelName,
    required this.backend,
  });

  final String text;
  final int elapsedMs;
  final String modelName;
  final String backend;

  factory LocalLlmGeneration.fromMap(Map<Object?, Object?> raw) =>
      LocalLlmGeneration(
        text: raw['text']?.toString().trim() ?? '',
        elapsedMs: (raw['elapsedMs'] as num?)?.toInt() ?? 0,
        modelName: raw['modelName']?.toString() ?? 'Modello locale',
        backend: raw['backend']?.toString() ?? 'CPU',
      );
}

abstract final class LocalLlmPolicy {
  static const runtime = 'LiteRT-LM 0.17.1';
  static const preferredModel = 'Gemma 3 270M IT';
  static const modelExtension = '.litertlm';
  static const minModelBytes = 32 * 1024 * 1024;
  static const maxModelBytes = 2 * 1024 * 1024 * 1024;
  static const maxQuestionChars = 4000;
  static const maxNoteContextChars = 16000;
  static const maxWorkspaceContextChars = 22000;
  static const maxWorkspaceSources = 6;
  static const defaultMaxOutputTokens = 384;

  static String notePrompt({
    required String question,
    required String title,
    required String body,
    List<String> tags = const [],
  }) {
    final safeQuestion = _trim(question, maxQuestionChars);
    final safeBody = _trim(body, maxNoteContextChars);
    final safeTitle = _trim(title, 500);
    final safeTags = tags.take(24).join(', ');
    return '''
DOMANDA
$safeQuestion

CONTESTO DELLA NOTA
Titolo: $safeTitle
${safeTags.isEmpty ? '' : 'Tag: $safeTags'}
Contenuto:
$safeBody

ISTRUZIONE
Rispondi usando prima di tutto il contesto fornito. Se il contesto non basta per una risposta affidabile, dichiaralo chiaramente. Non inventare dati mancanti.
'''
        .trim();
  }

  static String workspacePrompt({
    required String question,
    required Iterable<({String title, String excerpt})> sources,
  }) {
    final safeQuestion = _trim(question, maxQuestionChars);
    final buffer = StringBuffer()
      ..writeln('DOMANDA')
      ..writeln(safeQuestion)
      ..writeln()
      ..writeln('FONTI LOCALI DEL WORKSPACE');

    var remaining = maxWorkspaceContextChars;
    var index = 0;
    for (final source in sources.take(maxWorkspaceSources)) {
      if (remaining <= 0) break;
      index++;
      final title = _trim(source.title, 500);
      final excerpt = _trim(source.excerpt, remaining);
      final chunk = '[$index] $title\n$excerpt\n';
      if (chunk.length > remaining) break;
      buffer
        ..writeln(chunk)
        ..writeln();
      remaining -= chunk.length;
    }

    buffer
      ..writeln('ISTRUZIONE')
      ..writeln(
        'Rispondi solo sulla base delle fonti locali sopra. '
        'Quando utile cita le fonti con [1], [2], ecc. '
        'Se le fonti non contengono abbastanza informazioni, dillo esplicitamente. '
        'Non inventare fatti mancanti.',
      );
    return buffer.toString().trim();
  }

  static const systemInstruction = 'Sei il motore locale di Notes Ecosistema. '
      'Lavora esclusivamente con il contesto fornito dall’app. '
      'Sii conciso, concreto e verificabile. '
      'Non affermare di aver consultato Internet o fonti esterne.';

  static String _trim(String value, int maxChars) {
    final normalized = value.trim();
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars)}\n[…contenuto troncato…]';
  }
}
