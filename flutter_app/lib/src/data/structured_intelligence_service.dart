import '../domain/local_llm.dart';
import '../domain/structured_intelligence.dart';
import 'local_llm_service.dart';

class StructuredIntelligenceService {
  StructuredIntelligenceService({
    LocalLlmService? localLlm,
  }) : _localLlm = localLlm ?? LocalLlmService();

  final LocalLlmService _localLlm;

  Future<StructuredAnalysis> analyzeNote({
    required String title,
    required String body,
  }) async {
    final status = await _localLlm.status();
    if (!status.available || status.provider != LocalAiProvider.geminiNano) {
      return StructuredIntelligencePolicy.deterministic(body: body);
    }

    try {
      final generation = await _localLlm.generate(
        prompt: StructuredIntelligencePolicy.notePrompt(
          title: title,
          body: body,
        ),
        systemInstruction:
            'Sei il motore di structured intelligence locale di Notes Ecosistema. '
            'Restituisci esclusivamente JSON conforme allo schema richiesto. '
            'Non inventare dati e non proporre azioni distruttive o esterne.',
        maxOutputTokens: 512,
      );
      final parsed = StructuredIntelligencePolicy.parseGemini(
        generation.text,
        modelName: generation.modelName,
      );
      if (!parsed.empty) return parsed;
    } catch (_) {
      // Structured intelligence is optional: deterministic extraction remains
      // available even if the local generative provider fails.
    }

    return StructuredIntelligencePolicy.deterministic(body: body);
  }
}
