import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'note.dart';

enum StudyRating { again, hard, good, easy }

class LearningItem {
  const LearningItem({
    required this.id,
    required this.sourceNoteId,
    required this.sourceSnapshot,
    required this.sourceFingerprint,
    required this.sourceUpdatedAt,
    required this.prompt,
    required this.answer,
    required this.createdAt,
    required this.updatedAt,
    this.suspended = false,
  });

  final String id;
  final String sourceNoteId;
  final String sourceSnapshot;
  final String sourceFingerprint;
  final int sourceUpdatedAt;
  final String prompt;
  final String answer;
  final int createdAt;
  final int updatedAt;
  final bool suspended;

  Map<String, Object?> toMap() => {
        'id': id,
        'sourceNoteId': sourceNoteId,
        'sourceSnapshot': sourceSnapshot,
        'sourceFingerprint': sourceFingerprint,
        'sourceUpdatedAt': sourceUpdatedAt,
        'prompt': prompt,
        'answer': answer,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'suspended': suspended ? 1 : 0,
      };

  factory LearningItem.fromMap(Map<String, Object?> row) => LearningItem(
        id: row['id']?.toString() ?? '',
        sourceNoteId: row['sourceNoteId']?.toString() ?? '',
        sourceSnapshot: row['sourceSnapshot']?.toString() ?? '',
        sourceFingerprint: row['sourceFingerprint']?.toString() ?? '',
        sourceUpdatedAt: (row['sourceUpdatedAt'] as num?)?.toInt() ?? 0,
        prompt: row['prompt']?.toString() ?? '',
        answer: row['answer']?.toString() ?? '',
        createdAt: (row['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (row['updatedAt'] as num?)?.toInt() ?? 0,
        suspended: (row['suspended'] as num?)?.toInt() == 1,
      );
}

class ReviewState {
  const ReviewState({
    required this.itemId,
    required this.dueAt,
    required this.intervalDays,
    required this.ease,
    required this.repetitions,
    required this.lapses,
    this.lastReviewedAt,
  });

  final String itemId;
  final int dueAt;
  final int? lastReviewedAt;
  final int intervalDays;
  final double ease;
  final int repetitions;
  final int lapses;

  Map<String, Object?> toMap() => {
        'itemId': itemId,
        'dueAt': dueAt,
        'lastReviewedAt': lastReviewedAt,
        'intervalDays': intervalDays,
        'ease': ease,
        'repetitions': repetitions,
        'lapses': lapses,
      };

  factory ReviewState.fromMap(Map<String, Object?> row) => ReviewState(
        itemId: row['itemId']?.toString() ?? '',
        dueAt: (row['dueAt'] as num?)?.toInt() ?? 0,
        lastReviewedAt: (row['lastReviewedAt'] as num?)?.toInt(),
        intervalDays: (row['intervalDays'] as num?)?.toInt() ?? 0,
        ease: (row['ease'] as num?)?.toDouble() ?? 2.5,
        repetitions: (row['repetitions'] as num?)?.toInt() ?? 0,
        lapses: (row['lapses'] as num?)?.toInt() ?? 0,
      );
}

class ReviewLog {
  const ReviewLog({
    required this.id,
    required this.itemId,
    required this.rating,
    required this.reviewedAt,
    required this.previousDueAt,
    required this.nextDueAt,
    required this.intervalDays,
  });

  final String id;
  final String itemId;
  final StudyRating rating;
  final int reviewedAt;
  final int previousDueAt;
  final int nextDueAt;
  final int intervalDays;

  Map<String, Object?> toMap() => {
        'id': id,
        'itemId': itemId,
        'rating': rating.name,
        'reviewedAt': reviewedAt,
        'previousDueAt': previousDueAt,
        'nextDueAt': nextDueAt,
        'intervalDays': intervalDays,
      };

  factory ReviewLog.fromMap(Map<String, Object?> row) => ReviewLog(
        id: row['id']?.toString() ?? '',
        itemId: row['itemId']?.toString() ?? '',
        rating: StudyRating.values.firstWhere(
          (value) => value.name == row['rating']?.toString(),
          orElse: () => StudyRating.good,
        ),
        reviewedAt: (row['reviewedAt'] as num?)?.toInt() ?? 0,
        previousDueAt: (row['previousDueAt'] as num?)?.toInt() ?? 0,
        nextDueAt: (row['nextDueAt'] as num?)?.toInt() ?? 0,
        intervalDays: (row['intervalDays'] as num?)?.toInt() ?? 0,
      );
}

abstract interface class StudyScheduler {
  ReviewState next(
    ReviewState current,
    StudyRating rating, {
    required int reviewedAt,
  });
}

class SimpleStudyScheduler implements StudyScheduler {
  const SimpleStudyScheduler();

  static const _day = Duration.millisecondsPerDay;

  @override
  ReviewState next(
    ReviewState current,
    StudyRating rating, {
    required int reviewedAt,
  }) {
    var ease = current.ease.clamp(1.3, 3.0).toDouble();
    var repetitions = current.repetitions;
    var lapses = current.lapses;
    int interval;

    switch (rating) {
      case StudyRating.again:
        lapses++;
        repetitions = 0;
        ease = (ease - 0.2).clamp(1.3, 3.0).toDouble();
        interval = 0;
        break;
      case StudyRating.hard:
        repetitions++;
        ease = (ease - 0.05).clamp(1.3, 3.0).toDouble();
        interval = current.intervalDays <= 1
            ? 1
            : (current.intervalDays * 1.2).round().clamp(1, 36500).toInt();
        break;
      case StudyRating.good:
        repetitions++;
        interval = current.intervalDays == 0
            ? 1
            : current.intervalDays == 1
                ? 3
                : (current.intervalDays * ease).round().clamp(1, 36500).toInt();
        break;
      case StudyRating.easy:
        repetitions++;
        ease = (ease + 0.1).clamp(1.3, 3.0).toDouble();
        interval = current.intervalDays == 0
            ? 4
            : (current.intervalDays * ease * 1.3)
                .round()
                .clamp(1, 36500)
                .toInt();
        break;
    }

    final delay = rating == StudyRating.again
        ? const Duration(minutes: 10).inMilliseconds
        : interval * _day;

    return ReviewState(
      itemId: current.itemId,
      dueAt: reviewedAt + delay,
      lastReviewedAt: reviewedAt,
      intervalDays: interval,
      ease: ease,
      repetitions: repetitions,
      lapses: lapses,
    );
  }
}

abstract final class StudyRules {
  static const maxItems = 50000;
  static const maxText = 20000;

  static String fingerprint(String text) =>
      sha256.convert(utf8.encode(text)).toString();

  static LearningItem fromNote({
    required String id,
    required Note note,
    required String prompt,
    required String answer,
    required int now,
  }) {
    final snapshot = note.body.length <= maxText
        ? note.body
        : note.body.substring(0, maxText);
    final item = LearningItem(
      id: id,
      sourceNoteId: note.id,
      sourceSnapshot: snapshot,
      sourceFingerprint: fingerprint(note.body),
      sourceUpdatedAt: note.updatedAt,
      prompt: prompt.trim(),
      answer: answer.trim(),
      createdAt: now,
      updatedAt: now,
    );
    validateItem(item);
    return item;
  }

  static bool sourceChanged(LearningItem item, Note? source) =>
      source == null ||
      source.updatedAt != item.sourceUpdatedAt ||
      fingerprint(source.body) != item.sourceFingerprint;

  static void validateItem(LearningItem item) {
    if (item.id.trim().isEmpty ||
        item.sourceNoteId.trim().isEmpty ||
        item.prompt.trim().isEmpty ||
        item.answer.trim().isEmpty ||
        item.prompt.length > maxText ||
        item.answer.length > maxText ||
        item.sourceSnapshot.length > maxText ||
        item.createdAt < 0 ||
        item.updatedAt < item.createdAt) {
      throw const FormatException('Learning Item non valido.');
    }
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(item.sourceFingerprint)) {
      throw const FormatException('Fingerprint fonte non valido.');
    }
  }

  static void validateState(ReviewState state) {
    if (state.itemId.trim().isEmpty ||
        state.dueAt < 0 ||
        (state.lastReviewedAt ?? 0) < 0 ||
        state.intervalDays < 0 ||
        state.ease < 1.3 ||
        state.ease > 3.0 ||
        state.repetitions < 0 ||
        state.lapses < 0) {
      throw const FormatException('Review State non valido.');
    }
  }
}

abstract final class StudyQueue {
  static List<LearningItem> build({
    required Iterable<LearningItem> items,
    required Map<String, ReviewState> states,
    required int now,
    int maxDue = 60,
    int maxNew = 20,
  }) {
    final due = <LearningItem>[];
    final fresh = <LearningItem>[];

    for (final item in items) {
      if (item.suspended) continue;
      final state = states[item.id];
      if (state == null) {
        fresh.add(item);
      } else if (state.dueAt <= now) {
        due.add(item);
      }
    }

    due.sort((a, b) {
      final byDue = states[a.id]!.dueAt.compareTo(states[b.id]!.dueAt);
      return byDue != 0 ? byDue : a.createdAt.compareTo(b.createdAt);
    });
    fresh.sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return [
      ...due.take(maxDue),
      ...fresh.take(maxNew),
    ];
  }
}
