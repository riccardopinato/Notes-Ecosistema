import '../domain/local_llm.dart';
import '../domain/plus.dart';
import '../domain/structured_intelligence.dart';
import 'local_llm_service.dart';
import 'needle_runtime_service.dart';
import 'plus_entitlement_service.dart';

class StructuredIntelligenceService {
  StructuredIntelligenceService({
    LocalLlmService? localLlm,
    NeedleRuntimeService? needle,
    PlusEntitlementService? entitlements,
  })  : _localLlm = localLlm ?? LocalLlmService(),
        _needle = needle ?? const NeedleRuntimeService(),
        _entitlements = entitlements ?? const PlusEntitlementService();

  final LocalLlmService _localLlm;
  final NeedleRuntimeService _needle;
  final PlusEntitlementService _entitlements;

  Future<StructuredAnalysis> analyzeNote({
    required String title,
    required String body,
  }) async {
    final entitlement = await _entitlements.snapshot();
    if (entitlement.allows(PlusFeature.localAi20L)) {
      final needleResult = await _tryNeedle(
        title: title,
        body: body,
      );
      if (needleResult != null && !needleResult.empty) return needleResult;
    }

    final geminiResult = await _tryGemini(
      title: title,
      body: body,
    );
    if (geminiResult != null && !geminiResult.empty) return geminiResult;

    return StructuredIntelligencePolicy.deterministic(body: body);
  }

  Future<StructuredAnalysis?> _tryNeedle({
    required String title,
    required String body,
  }) async {
    try {
      final status = await _needle.status();
      if (!status.ready) return null;

      final generation = await _needle.analyze(
        StructuredIntelligencePolicy.needleNotePrompt(
          title: title,
          body: body,
        ),
      );
      return StructuredIntelligencePolicy.parseNeedleEnvelope(
        generation.text,
        modelName: generation.modelName,
      );
    } catch (_) {
      // Plus AI is optional. A runtime/model/device failure must never block
      // Gemini Nano or the deterministic core.
      return null;
    }
  }

  Future<StructuredAnalysis?> _tryGemini({
    required String title,
    required String body,
  }) async {
    try {
      final status = await _localLlm.status();
      if (!status.available || status.provider != LocalAiProvider.geminiNano) {
        return null;
      }

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
      return StructuredIntelligencePolicy.parseGemini(
        generation.text,
        modelName: generation.modelName,
      );
    } catch (_) {
      return null;
    }
  }
}
