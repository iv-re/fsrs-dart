import 'dart:math';

import 'package:fsrs_dart/src/card.dart';
import 'package:fsrs_dart/src/card_state.dart';
import 'package:fsrs_dart/src/fsrs.dart';
import 'package:fsrs_dart/src/history.dart';
import 'package:fsrs_dart/src/item_state.dart';
import 'package:fsrs_dart/src/memory_state.dart';
import 'package:fsrs_dart/src/next_states.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:fsrs_dart/src/review_log.dart';
import 'package:fsrs_dart/src/scheduling_result.dart';

/// Schedules cards using FSRS memory updates combined with short-term
/// learning and relearning steps.
class FsrsScheduler {
  FsrsScheduler({
    required this.fsrs,
    this.desiredRetention = 0.9,
    List<Duration> learningSteps = const [
      Duration(minutes: 1),
      Duration(minutes: 10),
    ],
    List<Duration> relearningSteps = const [
      Duration(minutes: 10),
    ],
    this.maximumInterval = 36500,
    this.enableShortTerm = true,
    this.enableFuzz = false,
    this.random,
  }) : learningSteps = List.unmodifiable(learningSteps),
       relearningSteps = List.unmodifiable(relearningSteps) {
    if (desiredRetention <= 0 || desiredRetention >= 1) {
      throw ArgumentError.value(
        desiredRetention,
        'desiredRetention',
        'must be between 0 and 1',
      );
    }
    if (maximumInterval < 1) {
      throw ArgumentError.value(
        maximumInterval,
        'maximumInterval',
        'must be at least 1',
      );
    }
  }

  /// The underlying FSRS algorithm instance.
  final Fsrs fsrs;

  /// The target retention probability (0.0 < desiredRetention < 1.0).
  final double desiredRetention;

  /// Intra-day steps for newly introduced cards.
  final List<Duration> learningSteps;

  /// Intra-day steps for forgotten review cards.
  final List<Duration> relearningSteps;

  /// The upper bound on scheduled review interval in days.
  final int maximumInterval;

  /// When true, intra-day learning and relearning steps are applied.
  /// When false, cards graduate directly using pure FSRS daily intervals.
  final bool enableShortTerm;

  /// Whether interval fuzzing is enabled to distribute review load.
  final bool enableFuzz;

  /// Optional pseudo-random number generator for interval fuzzing.
  final Random? random;

  static final Random _defaultRandom = Random();

  /// Creates a brand new unreviewed card.
  FsrsCard createEmptyCard({DateTime? now, int? cardId}) {
    return FsrsCard(
      due: (now ?? DateTime.now()).toUtc(),
      cardId: cardId,
    );
  }

  /// Previews the scheduling outcome for all ratings without mutating [card].
  FsrsRecordLog preview(
    FsrsCard card, {
    DateTime? reviewDate,
  }) {
    final reviewedAt = (reviewDate ?? DateTime.now().toUtc()).toUtc();
    final daysElapsed = _daysElapsed(card, reviewedAt);
    final nextStates = fsrs.nextStates(
      memoryState: card.memoryState,
      desiredRetention: desiredRetention,
      daysElapsed: daysElapsed,
    );

    return {
      for (final rating in FsrsRating.values)
        if (rating.isGrade)
          rating: _scheduleRating(
            card: card,
            rating: rating,
            reviewedAt: reviewedAt,
            itemState: _itemState(nextStates, rating),
            daysElapsed: daysElapsed,
          ),
    };
  }

  /// Applies [rating] to [card] and returns the resulting scheduling outcome.
  FsrsRecordLogItem reviewCard(
    FsrsCard card,
    FsrsRating rating, {
    DateTime? reviewDate,
  }) {
    if (!rating.isGrade) {
      throw ArgumentError.value(
        rating,
        'rating',
        'Cannot review a manual rating.',
      );
    }
    return preview(card, reviewDate: reviewDate)[rating]!;
  }

  /// Reverts a review given the card and the corresponding [log].
  FsrsCard rollback(FsrsCard card, FsrsReviewLog log) {
    final isNew = log.state == FsrsCardState.newCard;
    final lapseDecreased =
        card.lapses > 0 &&
        log.rating == FsrsRating.again &&
        log.state == FsrsCardState.review;

    final updatedReps = (card.reps - 1).clamp(0, 1000000);
    final updatedLapses = lapseDecreased ? card.lapses - 1 : card.lapses;

    if (isNew) {
      return card
          .reset(memoryState: true, lastReview: true)
          .copyWith(
            due: log.due,
            state: log.state,
            step: 0,
            reps: updatedReps,
            lapses: updatedLapses,
          );
    }

    return card.copyWith(
      due: log.due,
      state: log.state,
      step: card.step,
      reps: updatedReps,
      lapses: updatedLapses,
    );
  }

  /// Resets [card] to unlearned status.
  FsrsRecordLogItem forget(
    FsrsCard card, {
    DateTime? now,
    bool resetCount = false,
  }) {
    final resetAt = (now ?? DateTime.now()).toUtc();
    final newCard = card
        .reset(memoryState: true)
        .copyWith(
          due: resetAt,
          state: FsrsCardState.newCard,
          reps: resetCount ? 0 : card.reps,
          lapses: resetCount ? 0 : card.lapses,
          lastReview: resetAt,
        );

    final log = FsrsReviewLog(
      rating: FsrsRating.manual,
      state: card.state,
      due: resetAt,
      stability: 0,
      difficulty: 0,
      interval: Duration.zero,
      reviewedAt: resetAt,
    );

    return FsrsRecordLogItem(card: newCard, log: log);
  }

  /// Reschedules a card by replaying a sequence of historical [reviews].
  FsrsRescheduleResult reschedule(
    FsrsCard currentCard,
    List<FsrsHistoryEntry> reviews, {
    bool skipManual = true,
  }) {
    var curCard = createEmptyCard(
      now: currentCard.due,
      cardId: currentCard.cardId,
    );
    final sortedReviews = List<FsrsHistoryEntry>.from(reviews)
      ..sort((a, b) => a.review.compareTo(b.review));

    final collections = <FsrsRecordLogItem>[];

    for (final rev in sortedReviews) {
      if (rev.rating == FsrsRating.manual) {
        if (skipManual) continue;
        final reviewedAt = rev.review.toUtc();
        final due = (rev.due ?? reviewedAt).toUtc();
        final state = rev.state ?? curCard.state;
        final scheduledDays = due.difference(reviewedAt).inDays;
        final elapsedDays = curCard.lastReview != null
            ? reviewedAt.difference(curCard.lastReview!).inDays.clamp(0, 100000)
            : 0;

        final nextCard = curCard.copyWith(
          state: state,
          due: due,
          lastReview: reviewedAt,
          reps: curCard.reps + 1,
          memoryState: rev.stability != null && rev.difficulty != null
              ? FsrsMemoryState(
                  stability: rev.stability!,
                  difficulty: rev.difficulty!,
                )
              : curCard.memoryState,
        );

        final log = FsrsReviewLog(
          rating: FsrsRating.manual,
          state: curCard.state,
          due: curCard.due,
          stability: nextCard.stability ?? 0,
          difficulty: nextCard.difficulty ?? 0,
          interval: Duration(days: scheduledDays),
          reviewedAt: reviewedAt,
          elapsedDays: elapsedDays,
        );

        final item = FsrsRecordLogItem(card: nextCard, log: log);
        collections.add(item);
        curCard = nextCard;
      } else {
        final item = reviewCard(curCard, rev.rating, reviewDate: rev.review);
        collections.add(item);
        curCard = item.card;
      }
    }

    return FsrsRescheduleResult(collections: collections, card: curCard);
  }

  FsrsRecordLogItem _scheduleRating({
    required FsrsCard card,
    required FsrsRating rating,
    required DateTime reviewedAt,
    required FsrsItemState itemState,
    required int daysElapsed,
  }) {
    if (!enableShortTerm) {
      return _graduate(
        card: card,
        rating: rating,
        reviewedAt: reviewedAt,
        itemState: itemState,
        daysElapsed: daysElapsed,
      );
    }

    return switch (card.state) {
      FsrsCardState.newCard || FsrsCardState.learning => _scheduleStepCard(
        card: card,
        rating: rating,
        reviewedAt: reviewedAt,
        itemState: itemState,
        steps: learningSteps,
        stepState: FsrsCardState.learning,
        daysElapsed: daysElapsed,
      ),
      FsrsCardState.review => _scheduleReviewCard(
        card: card,
        rating: rating,
        reviewedAt: reviewedAt,
        itemState: itemState,
        daysElapsed: daysElapsed,
      ),
      FsrsCardState.relearning => _scheduleStepCard(
        card: card,
        rating: rating,
        reviewedAt: reviewedAt,
        itemState: itemState,
        steps: relearningSteps,
        stepState: FsrsCardState.relearning,
        daysElapsed: daysElapsed,
      ),
    };
  }

  FsrsRecordLogItem _scheduleReviewCard({
    required FsrsCard card,
    required FsrsRating rating,
    required DateTime reviewedAt,
    required FsrsItemState itemState,
    required int daysElapsed,
  }) {
    if (rating == FsrsRating.again && relearningSteps.isNotEmpty) {
      return _result(
        card: card,
        rating: rating,
        reviewedAt: reviewedAt,
        itemState: itemState,
        state: FsrsCardState.relearning,
        step: 0,
        interval: relearningSteps.first,
        lapses: card.lapses + 1,
        daysElapsed: daysElapsed,
      );
    }

    return _graduate(
      card: card,
      rating: rating,
      reviewedAt: reviewedAt,
      itemState: itemState,
      daysElapsed: daysElapsed,
      lapses: rating == FsrsRating.again ? card.lapses + 1 : card.lapses,
    );
  }

  FsrsRecordLogItem _scheduleStepCard({
    required FsrsCard card,
    required FsrsRating rating,
    required DateTime reviewedAt,
    required FsrsItemState itemState,
    required List<Duration> steps,
    required FsrsCardState stepState,
    required int daysElapsed,
  }) {
    final step = card.step;

    if (steps.isEmpty || (step >= steps.length && rating != FsrsRating.again)) {
      return _graduate(
        card: card,
        rating: rating,
        reviewedAt: reviewedAt,
        itemState: itemState,
        daysElapsed: daysElapsed,
      );
    }

    switch (rating) {
      case FsrsRating.again:
        return _result(
          card: card,
          rating: rating,
          reviewedAt: reviewedAt,
          itemState: itemState,
          state: stepState,
          step: 0,
          interval: steps.first,
          daysElapsed: daysElapsed,
        );
      case FsrsRating.hard:
        final interval = step == 0
            ? (steps.length == 1
                  ? _multiplyDuration(steps.first, 1.5)
                  : _averageDuration(steps[0], steps[1]))
            : steps[step];
        return _result(
          card: card,
          rating: rating,
          reviewedAt: reviewedAt,
          itemState: itemState,
          state: stepState,
          step: step,
          interval: interval,
          daysElapsed: daysElapsed,
        );
      case FsrsRating.good:
        if (step + 1 >= steps.length) {
          return _graduate(
            card: card,
            rating: rating,
            reviewedAt: reviewedAt,
            itemState: itemState,
            daysElapsed: daysElapsed,
          );
        }
        return _result(
          card: card,
          rating: rating,
          reviewedAt: reviewedAt,
          itemState: itemState,
          state: stepState,
          step: step + 1,
          interval: steps[step + 1],
          daysElapsed: daysElapsed,
        );
      case FsrsRating.easy:
        return _graduate(
          card: card,
          rating: rating,
          reviewedAt: reviewedAt,
          itemState: itemState,
          daysElapsed: daysElapsed,
        );
      case FsrsRating.manual:
        throw ArgumentError('Cannot review a manual rating.');
    }
  }

  FsrsRecordLogItem _graduate({
    required FsrsCard card,
    required FsrsRating rating,
    required DateTime reviewedAt,
    required FsrsItemState itemState,
    required int daysElapsed,
    int? lapses,
  }) {
    return _result(
      card: card,
      rating: rating,
      reviewedAt: reviewedAt,
      itemState: itemState,
      state: FsrsCardState.review,
      step: 0,
      interval: Duration(days: _reviewIntervalDays(itemState, daysElapsed)),
      daysElapsed: daysElapsed,
      lapses: lapses,
    );
  }

  FsrsRecordLogItem _result({
    required FsrsCard card,
    required FsrsRating rating,
    required DateTime reviewedAt,
    required FsrsItemState itemState,
    required FsrsCardState state,
    required int step,
    required Duration interval,
    required int daysElapsed,
    int? lapses,
  }) {
    final nextDue = reviewedAt.add(interval);
    final nextCard = card.copyWith(
      state: state,
      step: step,
      reps: card.reps + 1,
      lapses: lapses ?? card.lapses,
      memoryState: itemState.memory,
      due: nextDue,
      lastReview: reviewedAt,
    );

    final log = FsrsReviewLog(
      rating: rating,
      state: card.state,
      due: card.due,
      stability: itemState.memory.stability,
      difficulty: itemState.memory.difficulty,
      interval: interval,
      reviewedAt: reviewedAt,
      elapsedDays: daysElapsed,
    );

    return FsrsRecordLogItem(card: nextCard, log: log);
  }

  int _daysElapsed(FsrsCard card, DateTime reviewedAt) {
    final lastReview = card.lastReview;
    if (lastReview == null) {
      return 0;
    }
    final days = reviewedAt.difference(lastReview).inDays;
    return days < 0 ? 0 : days;
  }

  int _reviewIntervalDays(FsrsItemState itemState, int daysElapsed) {
    final rawInterval = itemState.interval;
    if (!enableFuzz || rawInterval < 2.5) {
      return rawInterval.round().clamp(1, maximumInterval);
    }
    return _applyFuzz(rawInterval, daysElapsed);
  }

  int _applyFuzz(double ivl, int elapsedDays) {
    var delta = 1.0;
    if (ivl > 2.5) {
      delta += 0.15 * (ivl.clamp(2.5, 7.0) - 2.5);
    }
    if (ivl > 7.0) {
      delta += 0.10 * (ivl.clamp(7.0, 20.0) - 7.0);
    }
    if (ivl > 20.0) {
      delta += 0.05 * (ivl - 20.0);
    }

    final boundedIvl = ivl.clamp(0.0, maximumInterval.toDouble());
    var minIvl = (boundedIvl - delta).round().clamp(2, maximumInterval);
    final maxIvl = (boundedIvl + delta).round().clamp(1, maximumInterval);

    if (boundedIvl > elapsedDays) {
      minIvl = minIvl.clamp(elapsedDays + 1, maximumInterval);
    }
    minIvl = minIvl.clamp(1, maxIvl);

    final rng = random ?? _defaultRandom;
    final range = maxIvl - minIvl + 1;
    return minIvl + (range > 1 ? rng.nextInt(range) : 0);
  }

  FsrsItemState _itemState(FsrsNextStates nextStates, FsrsRating rating) {
    return switch (rating) {
      FsrsRating.again => nextStates.again,
      FsrsRating.hard => nextStates.hard,
      FsrsRating.good => nextStates.good,
      FsrsRating.easy => nextStates.easy,
      FsrsRating.manual => throw ArgumentError(
        'No item state for manual rating',
      ),
    };
  }
}

Duration _averageDuration(Duration first, Duration second) {
  return Duration(
    microseconds: ((first.inMicroseconds + second.inMicroseconds) / 2).round(),
  );
}

Duration _multiplyDuration(Duration duration, double factor) {
  return Duration(
    microseconds: (duration.inMicroseconds * factor).round(),
  );
}
