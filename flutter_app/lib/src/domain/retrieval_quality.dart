class RetrievalQualityCase {
  const RetrievalQualityCase({
    required this.query,
    required this.relevantIds,
  });

  final String query;
  final Set<String> relevantIds;
}

class RetrievalQualityReport {
  const RetrievalQualityReport({
    required this.cases,
    required this.recallAtK,
    required this.meanReciprocalRank,
  });

  final int cases;
  final double recallAtK;
  final double meanReciprocalRank;
}

abstract final class RetrievalQuality {
  static RetrievalQualityReport evaluate({
    required List<RetrievalQualityCase> cases,
    required List<String> Function(String query) ranker,
    int k = 3,
  }) {
    if (cases.isEmpty) {
      throw const FormatException('Dataset qualità retrieval vuoto.');
    }
    if (k < 1 || k > 100) {
      throw const FormatException('Valore K non valido.');
    }

    var recallSum = 0.0;
    var reciprocalRankSum = 0.0;

    for (final testCase in cases) {
      if (testCase.query.trim().isEmpty || testCase.relevantIds.isEmpty) {
        throw const FormatException('Caso qualità retrieval non valido.');
      }
      final ranked = ranker(testCase.query);
      final top = ranked.take(k).toSet();
      final recovered =
          top.where(testCase.relevantIds.contains).length.toDouble();
      recallSum += recovered / testCase.relevantIds.length;

      var reciprocalRank = 0.0;
      for (var i = 0; i < ranked.length; i++) {
        if (testCase.relevantIds.contains(ranked[i])) {
          reciprocalRank = 1 / (i + 1);
          break;
        }
      }
      reciprocalRankSum += reciprocalRank;
    }

    return RetrievalQualityReport(
      cases: cases.length,
      recallAtK: recallSum / cases.length,
      meanReciprocalRank: reciprocalRankSum / cases.length,
    );
  }
}
