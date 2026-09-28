enum StudyRating { again, hard, good, easy }

class LearningItem {
  const LearningItem({
    required this.id,
    required this.sourceNoteId,
    required this.prompt,
    required this.answer,
    required this.sourceSnapshot,
    required this.sourceUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String sourceNoteId;
  final String prompt;
  final String answer;
  final String sourceSnapshot;
  final int sourceUpdatedAt;
  final int createdAt;
  final int updatedAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'sourceNoteId': sourceNoteId,
        'prompt': prompt,
        'answer': answer,
        'sourceSnapshot': sourceSnapshot,
        'sourceUpdatedAt': sourceUpdatedAt,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory LearningItem.fromMap(Map<String, Object?> row) => LearningItem(
        id: row['id']?.toString() ?? '',
        sourceNoteId: row['sourceNoteId']?.toString() ?? '',
        prompt: row['prompt']?.toString() ?? '',
        answer: row['answer']?.toString() ?? '',
        sourceSnapshot: row['sourceSnapshot']?.toString() ?? '',
        sourceUpdatedAt: (row['sourceUpdatedAt'] as num?)?.toInt() ?? 0,
        createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class ReviewLog {
  const ReviewLog({
    required this.id,
    required this.itemId,
    required this.reviewedAt,
    required this.rating,
    required this.intervalDays,
  });

  final String id;
  final String itemId;
  final int reviewedAt;
  final StudyRating rating;
  final int intervalDays;

  Map<String, Object?> toMap() => {
        'id': id,
        'itemId': itemId,
        'reviewedAt': reviewedAt,
        'rating': rating.name,
        'intervalDays': intervalDays,
      };

  factory ReviewLog.fromMap(Map<String, Object?> row) {
    final ratingName = row['rating']?.toString() ?? '';
    final rating =
        StudyRating.values.where((value) => value.name == ratingName);
    if (rating.isEmpty) {
      throw const FormatException('Valutazione ripasso non valida.');
    }
    return ReviewLog(
      id: row['id']?.toString() ?? '',
      itemId: row['itemId']?.toString() ?? '',
      reviewedAt: (row['reviewedAt'] as num?)?.toInt() ?? 0,
      rating: rating.first,
      intervalDays: (row['intervalDays'] as num?)?.toInt() ?? 0,
    );
  }
}

class ReviewState {
  const ReviewState({
    required this.itemId,
    required this.dueAt,
    required this.intervalDays,
    required this.reviewCount,
  });

  final String itemId;
  final int dueAt;
  final int intervalDays;
  final int reviewCount;

  bool isDue(int now) => dueAt <= now;
}

abstract class StudyScheduler {
  const StudyScheduler();

  ReviewState stateFor(
    LearningItem item,
    List<ReviewLog> logs, {
    required int now,
  });

  int nextIntervalDays(ReviewState current, StudyRating rating);
}

class SimpleStudyScheduler extends StudyScheduler {
  const SimpleStudyScheduler();

  static const dayMillis = 24 * 60 * 60 * 1000;

  @override
  ReviewState stateFor(
    LearningItem item,
    List<ReviewLog> logs, {
    required int now,
  }) {
    final ordered = logs.where((log) => log.itemId == item.id).toList()
      ..sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
    if (ordered.isEmpty) {
      return ReviewState(
        itemId: item.id,
        dueAt: item.createdAt,
        intervalDays: 0,
        reviewCount: 0,
      );
    }
    final last = ordered.last;
    return ReviewState(
      itemId: item.id,
      dueAt: last.reviewedAt + last.intervalDays * dayMillis,
      intervalDays: last.intervalDays,
      reviewCount: ordered.length,
    );
  }

  @override
  int nextIntervalDays(ReviewState current, StudyRating rating) {
    final previous = current.intervalDays;
    return switch (rating) {
      StudyRating.again => 1,
      StudyRating.hard => previous <= 1 ? 2 : (previous * 1.5).round(),
      StudyRating.good => previous <= 1 ? 3 : (previous * 2.2).round(),
      StudyRating.easy => previous <= 1 ? 5 : (previous * 3.0).round(),
    }
        .clamp(1, 3650);
  }
}

abstract final class StudyQueue {
  static const defaultDailyLimit = 30;

  static List<LearningItem> due({
    required List<LearningItem> items,
    required List<ReviewLog> logs,
    required int now,
    StudyScheduler scheduler = const SimpleStudyScheduler(),
    int limit = defaultDailyLimit,
  }) {
    final candidates = [
      for (final item in items)
        (
          item: item,
          state: scheduler.stateFor(item, logs, now: now),
        ),
    ].where((entry) => entry.state.isDue(now)).toList();

    candidates.sort((a, b) {
      final due = a.state.dueAt.compareTo(b.state.dueAt);
      if (due != 0) return due;
      final reviews = a.state.reviewCount.compareTo(b.state.reviewCount);
      if (reviews != 0) return reviews;
      return a.item.id.compareTo(b.item.id);
    });
    return candidates
        .take(limit.clamp(1, 100))
        .map((entry) => entry.item)
        .toList(growable: false);
  }
}

abstract final class StudyRules {
  static const maxItems = 10000;
  static const maxPrompt = 4000;
  static const maxAnswer = 20000;
  static const maxSnapshot = 50000;

  static void validateItem(LearningItem item) {
    if (item.id.trim().isEmpty ||
        item.sourceNoteId.trim().isEmpty ||
        item.prompt.trim().isEmpty ||
        item.prompt.length > maxPrompt ||
        item.answer.trim().isEmpty ||
        item.answer.length > maxAnswer ||
        item.sourceSnapshot.length > maxSnapshot ||
        item.sourceUpdatedAt < 0 ||
        item.createdAt < 0 ||
        item.updatedAt < 0) {
      throw const FormatException('Elemento di studio non valido.');
    }
  }

  static void validateLog(ReviewLog log) {
    if (log.id.trim().isEmpty ||
        log.itemId.trim().isEmpty ||
        log.reviewedAt < 0 ||
        log.intervalDays < 1 ||
        log.intervalDays > 3650) {
      throw const FormatException('Ripasso non valido.');
    }
  }
}
