enum LocalAiProvider { geminiNano, needle, semantic }

class LocalLlmStatus {
  const LocalLlmStatus({
    required this.supported,
    required this.available,
    required this.downloadable,
    required this.downloading,
    required this.runtime,
    required this.backend,
    required this.modelName,
    required this.systemManaged,
    required this.provider,
    this.error,
  });

  final bool supported;
  final bool available;
  final bool downloadable;
  final bool downloading;
  final String runtime;
  final String backend;
  final String modelName;
  final bool systemManaged;
  final LocalAiProvider provider;
  final String? error;

  factory LocalLlmStatus.fromMap(Map<Object?, Object?> raw) {
    final provider = switch (raw['provider']?.toString()) {
      'geminiNano' => LocalAiProvider.geminiNano,
      'needle' => LocalAiProvider.needle,
      _ => LocalAiProvider.semantic,
    };
    return LocalLlmStatus(
      supported: raw['supported'] == true,
      available: raw['available'] == true,
      downloadable: raw['downloadable'] == true,
      downloading: raw['downloading'] == true,
      runtime: raw['runtime']?.toString() ?? LocalLlmPolicy.runtime,
      backend: raw['backend']?.toString() ?? 'AICore',
      modelName: raw['modelName']?.toString() ?? LocalLlmPolicy.preferredModel,
      systemManaged: raw['systemManaged'] != false,
      provider: provider,
      error: raw['error']?.toString(),
    );
  }

  factory LocalLlmStatus.unsupported([String? error]) => LocalLlmStatus(
        supported: false,
        available: false,
        downloadable: false,
        downloading: false,
        runtime: LocalLlmPolicy.runtime,
        backend: 'Semantic Retrieval',
        modelName: LocalLlmPolicy.preferredModel,
        systemManaged: true,
        provider: LocalAiProvider.semantic,
        error: error,
      );
}

class LocalLlmGeneration {
  const LocalLlmGeneration({
    required this.text,
    required this.elapsedMs,
    required this.modelName,
    required this.backend,
    required this.provider,
  });

  final String text;
  final int elapsedMs;
  final String modelName;
  final String backend;
  final LocalAiProvider provider;

  factory LocalLlmGeneration.fromMap(Map<Object?, Object?> raw) {
    final provider = switch (raw['provider']?.toString()) {
      'needle' => LocalAiProvider.needle,
      'semantic' => LocalAiProvider.semantic,
      _ => LocalAiProvider.geminiNano,
    };
    return LocalLlmGeneration(
      text: raw['text']?.toString().trim() ?? '',
      elapsedMs: (raw['elapsedMs'] as num?)?.toInt() ?? 0,
      modelName: raw['modelName']?.toString() ?? LocalLlmPolicy.preferredModel,
      backend: raw['backend']?.toString() ?? 'AICore',
      provider: provider,
    );
  }
}

abstract final class LocalLlmPolicy {
  static const runtime = 'Android AICore / ML Kit Prompt API';
  static const preferredModel = 'Gemini Nano';
  static const lightweightFallback = 'Needle 3';
  static const maxQuestionChars = 3500;
  static const maxNoteContextChars = 10000;
  static const maxWorkspaceContextChars = 12000;
  static const maxWorkspaceSources = 5;
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
Rispondi usando il contesto fornito. Se il contesto non basta per una risposta affidabile, dichiaralo chiaramente. Non inventare dati mancanti.
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
