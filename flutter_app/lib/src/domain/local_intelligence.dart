import 'dart:math' as math;

import 'intelligence.dart';
import 'note.dart';
import 'unified_retrieval.dart';

enum LocalModelCapability { embeddings, structuredExtraction, toolCalling }

enum LocalModelRole { shipCandidate, control, qualityReference }

class LocalModelCandidate {
  const LocalModelCandidate({
    required this.id,
    required this.name,
    required this.license,
    required this.minWeightBytes,
    required this.maxWeightBytes,
    required this.languages,
    required this.capabilities,
    required this.role,
    required this.summary,
    this.embeddingDimensions,
    this.mobileAbiNote,
  });

  final String id;
  final String name;
  final String license;
  final int minWeightBytes;
  final int maxWeightBytes;
  final Set<String> languages;
  final Set<LocalModelCapability> capabilities;
  final LocalModelRole role;
  final String summary;
  final int? embeddingDimensions;
  final String? mobileAbiNote;

  bool get supportsAllProductLanguages {
    const required = {'it', 'en', 'es', 'fr', 'de', 'pt'};
    return languages.contains('multilingual') || languages.containsAll(required);
  }

  double get maxWeightMb => maxWeightBytes / (1024 * 1024);
}

abstract final class LocalModelAudit {
  static const candidates = <LocalModelCandidate>[
    LocalModelCandidate(
      id: 'needle3',
      name: 'Needle 3',
      license: 'Apache-2.0',
      minWeightBytes: 8 * 1024 * 1024,
      maxWeightBytes: 35 * 1024 * 1024,
      languages: {'unverified-multilingual'},
      capabilities: {
        LocalModelCapability.embeddings,
        LocalModelCapability.structuredExtraction,
        LocalModelCapability.toolCalling,
      },
      role: LocalModelRole.shipCandidate,
      summary:
          'Unico candidato ultra-compatto multifunzione. La qualità semantic '
          'search sulle sei lingue di Notes deve essere validata prima del rollout.',
      embeddingDimensions: 128,
      mobileAbiNote:
          'Runtime Needle nativo disponibile su Android ARM64/ARMv7; '
          'binding Flutter Cactus corrente documentato per ARM64.',
    ),
    LocalModelCandidate(
      id: 'minilm-l6-v2-qint8',
      name: 'all-MiniLM-L6-v2 qint8',
      license: 'Apache-2.0',
      minWeightBytes: 23 * 1024 * 1024,
      maxWeightBytes: 25 * 1024 * 1024,
      languages: {'en'},
      capabilities: {LocalModelCapability.embeddings},
      role: LocalModelRole.control,
      summary:
          'Controllo leggero e maturo per inglese; non idoneo come default '
          'per Notes multilingua.',
      embeddingDimensions: 384,
    ),
    LocalModelCandidate(
      id: 'bge-small-en-v1.5-int8',
      name: 'BGE small EN v1.5 int8',
      license: 'MIT',
      minWeightBytes: 34 * 1024 * 1024,
      maxWeightBytes: 36 * 1024 * 1024,
      languages: {'en'},
      capabilities: {LocalModelCapability.embeddings},
      role: LocalModelRole.control,
      summary:
          'Retrieval specialist compatto, ma English-only: utile come controllo '
          'di qualità, non come modello prodotto.',
      embeddingDimensions: 384,
    ),
    LocalModelCandidate(
      id: 'multilingual-e5-small-int8',
      name: 'multilingual-e5-small int8',
      license: 'MIT',
      minWeightBytes: 118 * 1024 * 1024,
      maxWeightBytes: 145 * 1024 * 1024,
      languages: {'multilingual'},
      capabilities: {LocalModelCapability.embeddings},
      role: LocalModelRole.qualityReference,
      summary:
          'Riferimento multilingua per il benchmark. Troppo grande per il '
          'pack mobile leggero desiderato.',
      embeddingDimensions: 384,
    ),
  ];

  static LocalModelCandidate get needle =>
      candidates.firstWhere((candidate) => candidate.id == 'needle3');
}

class SemanticVector {
  SemanticVector(List<double> values)
      : values = List.unmodifiable(values),
        norm = _norm(values) {
    if (values.isEmpty || values.length > 4096 || norm == 0) {
      throw const FormatException('Embedding locale non valido.');
    }
    if (values.any((value) => !value.isFinite)) {
      throw const FormatException('Embedding locale non finito.');
    }
  }

  final List<double> values;
  final double norm;

  static double cosine(SemanticVector a, SemanticVector b) {
    if (a.values.length != b.values.length) {
      throw const FormatException('Dimensioni embedding incompatibili.');
    }
    var dot = 0.0;
    for (var index = 0; index < a.values.length; index++) {
      dot += a.values[index] * b.values[index];
    }
    return (dot / (a.norm * b.norm)).clamp(-1.0, 1.0).toDouble();
  }

  static double _norm(List<double> values) {
    var squared = 0.0;
    for (final value in values) {
      squared += value * value;
    }
    return math.sqrt(squared);
  }
}

abstract interface class SemanticEmbeddingProvider {
  String get modelId;
  String get modelVersion;
  int get dimensions;
  bool get telemetryDisabled;

  Future<bool> isAvailable();
  Future<SemanticVector> embed(String text);

  Future<List<SemanticVector>> embedBatch(List<String> texts) async {
    final result = <SemanticVector>[];
    for (final text in texts) {
      result.add(await embed(text));
    }
    return result;
  }
}

class SemanticScore {
  const SemanticScore({
    required this.documentId,
    required this.noteId,
    required this.score,
  });

  final String documentId;
  final String noteId;
  final double score;
}

abstract final class HybridSemanticRanker {
  static List<KnowledgeHit> rank({
    required String query,
    required List<RetrievalDocument> documents,
    required List<RetrievalHit> lexicalHits,
    required List<SemanticScore> semanticScores,
    required List<Note> notes,
    int limit = 8,
    double semanticWeight = 0.58,
  }) {
    if (semanticWeight < 0 || semanticWeight > 1) {
      throw const FormatException('Peso semantico non valido.');
    }
    final byNote = {for (final note in notes) note.id: note};
    final docs = {for (final document in documents) document.id: document};
    final lexicalByNote = <String, double>{};
    var lexicalMax = 0.0;
    for (final hit in lexicalHits) {
      lexicalMax = math.max(lexicalMax, hit.score);
      lexicalByNote.update(
        hit.document.noteId,
        (value) => math.max(value, hit.score),
        ifAbsent: () => hit.score,
      );
    }

    final semanticByNote = <String, double>{};
    for (final score in semanticScores) {
      if (!docs.containsKey(score.documentId)) continue;
      final normalized =
          ((score.score + 1) / 2).clamp(0.0, 1.0).toDouble();
      semanticByNote.update(
        score.noteId,
        (value) => math.max(value, normalized),
        ifAbsent: () => normalized,
      );
    }

    final noteIds = <String>{
      ...lexicalByNote.keys,
      ...semanticByNote.keys,
    };
    final ranked = <({Note note, double score})>[];
    for (final noteId in noteIds) {
      final note = byNote[noteId];
      if (note == null || note.isDeleted || note.archived) continue;
      final lexical = lexicalMax <= 0
          ? 0.0
          : (lexicalByNote[noteId] ?? 0) / lexicalMax;
      final semantic = semanticByNote[noteId] ?? 0.0;
      if (lexical <= 0 && semantic < 0.55) continue;
      final score =
          lexical * (1 - semanticWeight) + semantic * semanticWeight;
      ranked.add((note: note, score: score));
    }
    ranked.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final byUpdated = b.note.updatedAt.compareTo(a.note.updatedAt);
      if (byUpdated != 0) return byUpdated;
      return a.note.id.compareTo(b.note.id);
    });

    return ranked.take(limit.clamp(1, 30)).map((row) {
      return KnowledgeHit(
        note: row.note,
        score: row.score,
        excerpt: UnifiedRetrieval.excerpt(row.note.body, query),
      );
    }).toList(growable: false);
  }
}

class SemanticBenchmarkCase {
  const SemanticBenchmarkCase({
    required this.id,
    required this.language,
    required this.query,
    required this.expectedDocumentId,
  });

  final String id;
  final String language;
  final String query;
  final String expectedDocumentId;
}

class SemanticBenchmarkResult {
  const SemanticBenchmarkResult({
    required this.modelId,
    required this.modelVersion,
    required this.total,
    required this.top1,
    required this.meanReciprocalRank,
    required this.perLanguageTop1,
    required this.elapsedMilliseconds,
  });

  final String modelId;
  final String modelVersion;
  final int total;
  final int top1;
  final double meanReciprocalRank;
  final Map<String, double> perLanguageTop1;
  final int elapsedMilliseconds;

  double get top1Accuracy => total == 0 ? 0.0 : top1 / total;

  bool get passesNotesGate {
    if (total == 0 || top1Accuracy < 0.78 || meanReciprocalRank < 0.84) {
      return false;
    }
    return perLanguageTop1.values.every((value) => value >= 0.60);
  }
}

class SemanticBenchmarkCorpus {
  const SemanticBenchmarkCorpus({
    required this.documents,
    required this.cases,
  });

  final Map<String, String> documents;
  final List<SemanticBenchmarkCase> cases;

  static const notesMultilingual = SemanticBenchmarkCorpus(
    documents: {
      'travel': 'Pianificare un viaggio in montagna con sentieri, rifugi e meteo.',
      'finance': 'Budget mensile, spese ricorrenti, risparmio e investimenti.',
      'study': 'Preparare un esame con domande, ripasso e spaced repetition.',
      'project': 'Organizzare progetto, milestone, task, scadenze e collaboratori.',
      'health': 'Allenamento, recupero, sonno e abitudini di benessere.',
      'documents': 'PDF, annotazioni, OCR e ricerca dentro documenti.',
    },
    cases: [
      SemanticBenchmarkCase(
        id: 'it-travel',
        language: 'it',
        query: 'idee per escursioni e rifugi in montagna',
        expectedDocumentId: 'travel',
      ),
      SemanticBenchmarkCase(
        id: 'it-study',
        language: 'it',
        query: 'come organizzare il ripasso per un esame',
        expectedDocumentId: 'study',
      ),
      SemanticBenchmarkCase(
        id: 'en-finance',
        language: 'en',
        query: 'track monthly expenses and savings',
        expectedDocumentId: 'finance',
      ),
      SemanticBenchmarkCase(
        id: 'en-documents',
        language: 'en',
        query: 'search text extracted from a PDF',
        expectedDocumentId: 'documents',
      ),
      SemanticBenchmarkCase(
        id: 'es-project',
        language: 'es',
        query: 'gestionar tareas y fechas de un proyecto',
        expectedDocumentId: 'project',
      ),
      SemanticBenchmarkCase(
        id: 'es-health',
        language: 'es',
        query: 'rutina de entrenamiento y recuperación',
        expectedDocumentId: 'health',
      ),
      SemanticBenchmarkCase(
        id: 'fr-study',
        language: 'fr',
        query: 'réviser efficacement avant un examen',
        expectedDocumentId: 'study',
      ),
      SemanticBenchmarkCase(
        id: 'fr-travel',
        language: 'fr',
        query: 'randonnées et refuges en montagne',
        expectedDocumentId: 'travel',
      ),
      SemanticBenchmarkCase(
        id: 'de-finance',
        language: 'de',
        query: 'monatliche Ausgaben und Sparziele verwalten',
        expectedDocumentId: 'finance',
      ),
      SemanticBenchmarkCase(
        id: 'de-project',
        language: 'de',
        query: 'Aufgaben Meilensteine und Fristen planen',
        expectedDocumentId: 'project',
      ),
      SemanticBenchmarkCase(
        id: 'pt-health',
        language: 'pt',
        query: 'treino recuperação e hábitos de sono',
        expectedDocumentId: 'health',
      ),
      SemanticBenchmarkCase(
        id: 'pt-documents',
        language: 'pt',
        query: 'encontrar texto e anotações em arquivos PDF',
        expectedDocumentId: 'documents',
      ),
    ],
  );
}

abstract final class SemanticBenchmark {
  static Future<SemanticBenchmarkResult> run({
    required SemanticEmbeddingProvider provider,
    SemanticBenchmarkCorpus corpus = SemanticBenchmarkCorpus.notesMultilingual,
  }) async {
    if (!await provider.isAvailable()) {
      throw StateError('Provider semantico non disponibile.');
    }
    final watch = Stopwatch()..start();
    final documentIds = corpus.documents.keys.toList(growable: false);
    final documentVectors = await provider.embedBatch(
      [for (final id in documentIds) corpus.documents[id]!],
    );
    final perLanguage = <String, ({int total, int hits})>{};
    var top1 = 0;
    var reciprocal = 0.0;

    for (final testCase in corpus.cases) {
      final query = await provider.embed(testCase.query);
      final ranked = <({String id, double score})>[];
      for (var index = 0; index < documentIds.length; index++) {
        ranked.add(
          (
            id: documentIds[index],
            score: SemanticVector.cosine(query, documentVectors[index]),
          ),
        );
      }
      ranked.sort((a, b) {
        final score = b.score.compareTo(a.score);
        return score != 0 ? score : a.id.compareTo(b.id);
      });
      final rank = ranked.indexWhere(
            (row) => row.id == testCase.expectedDocumentId,
          ) +
          1;
      final hit = rank == 1;
      if (hit) top1++;
      if (rank > 0) reciprocal += 1 / rank;
      final current =
          perLanguage[testCase.language] ?? (total: 0, hits: 0);
      perLanguage[testCase.language] = (
        total: current.total + 1,
        hits: current.hits + (hit ? 1 : 0),
      );
    }
    watch.stop();

    return SemanticBenchmarkResult(
      modelId: provider.modelId,
      modelVersion: provider.modelVersion,
      total: corpus.cases.length,
      top1: top1,
      meanReciprocalRank:
          corpus.cases.isEmpty ? 0 : reciprocal / corpus.cases.length,
      perLanguageTop1: {
        for (final entry in perLanguage.entries)
          entry.key:
              entry.value.total == 0
                  ? 0.0
                  : entry.value.hits / entry.value.total,
      },
      elapsedMilliseconds: watch.elapsedMilliseconds,
    );
  }
}
