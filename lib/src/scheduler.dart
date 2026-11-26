import 'dart:math';

import 'package:fsrs_dart/src/card.dart';
import 'package:fsrs_dart/src/history.dart';
import 'package:fsrs_dart/src/memory_state.dart';
import 'package:fsrs_dart/src/model.dart';
import 'package:fsrs_dart/src/native.dart' show toDays;
import 'package:fsrs_dart/src/next_states.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:fsrs_dart/src/review_log.dart';
import 'package:fsrs_dart/src/scheduling_result.dart';

final class FsrsScheduler {
  /// [model] defaults to `FsrsModel()`. Steps are ignored if
  /// [enableShortTerm] is false.
  ///
  /// Throws [ArgumentError] for a retention outside (0, 1), a non-positive
  /// step, or a [maximumInterval] shorter than one day.
  FsrsScheduler({
    FsrsModel? model,
    this.desiredRetention = 0.9,
    List<Duration> learningSteps = const [
      Duration(minutes: 1),
      Duration(minutes: 10),
    ],
    List<Duration> relearningSteps = const [Duration(minutes: 10)],
    this.maximumInterval = const Duration(days: 36500),
    this.enableShortTerm = true,
    this.enableFuzz = false,
    this.fuzzSeed = 0,
  }) : model = model ?? FsrsModel(),
       learningSteps = List.unmodifiable(learningSteps),
       relearningSteps = List.unmodifiable(relearningSteps) {
    _checkRetention(desiredRetention);
    for (final (steps, name) in [
      (this.learningSteps, 'learningSteps'),
      (this.relearningSteps, 'relearningSteps'),
    ]) {
      if (steps.any((step) => step <= Duration.zero)) {
        throw ArgumentError.value(steps, name, 'steps must be positive');
      }
    }
    if (maximumInterval.inDays < 1) {
      throw ArgumentError.value(
        maximumInterval,
        'maximumInterval',
        'must be at least one day',
      );
    }
  }

  final FsrsModel model;

  final double desiredRetention;

  final List<Duration> learningSteps;

  final List<Duration> relearningSteps;

  /// Whole days.
  final Duration maximumInterval;

  final bool enableShortTerm;

  final bool enableFuzz;

  final int fuzzSeed;

  int get _maximumDays => maximumInterval.inDays;

  /// [desiredRetention] overrides [FsrsScheduler.desiredRetention].
  FsrsPreview preview(
    FsrsCard card, {
    DateTime? now,
    double? desiredRetention,
  }) {
    final review = _Review(this, card, now, desiredRetention);
    return FsrsPreview(
      again: review.apply(.again),
      hard: review.apply(.hard),
      good: review.apply(.good),
      easy: review.apply(.easy),
    );
  }

  /// [desiredRetention] overrides [FsrsScheduler.desiredRetention].
  FsrsReviewResult review(
    FsrsCard card,
    FsrsRating rating, {
    DateTime? now,
    double? desiredRetention,
  }) => _Review(this, card, now, desiredRetention).apply(rating);

  /// `null` for a new card.
  double? retrievability(FsrsCard card, {DateTime? now}) => switch (card) {
    FsrsNewCard() => null,
    FsrsActiveCard(:final memory, :final lastReview) => model.retrievability(
      memory,
      _elapsed(lastReview, (now ?? DateTime.now()).toUtc()),
    ),
  };

  /// Throws [ArgumentError] if the ids of [card] and [log] differ.
  FsrsCard undo(FsrsCard card, FsrsReviewLog log) {
    if (card.id != null && log.cardId != null && card.id != log.cardId) {
      throw ArgumentError.value(
        log,
        'log',
        'belongs to card ${log.cardId}, not ${card.id}',
      );
    }
    return log.cardBefore;
  }

  FsrsReviewResult forget(
    FsrsCard card, {
    DateTime? now,
    bool resetCounts = false,
  }) {
    final at = (now ?? DateTime.now()).toUtc();
    final forgotten = FsrsNewCard(
      id: card.id,
      due: at,
      reps: resetCounts ? 0 : card.reps,
      lapses: resetCounts ? 0 : card.lapses,
    );
    return (
      card: forgotten,
      log: _log(card, reviewedAt: at, interval: Duration.zero),
    );
  }

  /// Replays [history] in chronological order on a new card with the id of
  /// [card].
  FsrsRescheduleResult reschedule(
    FsrsCard card,
    List<FsrsHistoryEntry> history,
  ) {
    final entries = history.indexed.toList()
      ..sort((a, b) {
        final byTime = a.$2.at.compareTo(b.$2.at);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });

    FsrsCard current = FsrsNewCard(
      id: card.id,
      due: entries.isEmpty ? card.due : entries.first.$2.at,
    );
    final logs = <FsrsReviewLog>[];
    for (final (_, entry) in entries) {
      final result = switch (entry) {
        FsrsHistoryReview(:final at, :final rating) => review(
          current,
          rating,
          now: at,
        ),
        final FsrsHistoryManual manual => _manual(current, manual),
      };
      current = result.card;
      logs.add(result.log);
    }
    return FsrsRescheduleResult(card: current, logs: logs);
  }

  FsrsReviewResult _manual(FsrsCard card, FsrsHistoryManual entry) {
    final next = switch (card) {
      FsrsActiveCard() => card.copyWith(
        due: entry.due,
        phase: entry.phase,
        step: entry.phase == null || entry.phase == card.phase ? card.step : 0,
        memory: entry.memory,
        lastReview: entry.memory == null ? card.lastReview : entry.at,
      ),
      FsrsNewCard() => switch ((entry.phase, entry.memory)) {
        (null, null) => card.copyWith(due: entry.due),
        (final FsrsPhase phase, final FsrsMemoryState memory) => FsrsActiveCard(
          id: card.id,
          phase: phase,
          memory: memory,
          due: entry.due,
          lastReview: entry.at,
          reps: card.reps,
          lapses: card.lapses,
        ),
        _ => throw ArgumentError.value(
          entry,
          'history',
          'a manual entry makes a new card active only with both phase and '
              'memory',
        ),
      },
    };
    return (
      card: next,
      log: _log(
        card,
        reviewedAt: entry.at,
        interval: entry.due.difference(entry.at),
      ),
    );
  }

  static FsrsReviewLog _log(
    FsrsCard before, {
    required DateTime reviewedAt,
    required Duration interval,
    FsrsRating? rating,
    Duration elapsed = Duration.zero,
  }) => switch (before) {
    FsrsNewCard() => FsrsReviewLog(
      cardId: before.id,
      rating: rating,
      reviewedAt: reviewedAt,
      elapsed: elapsed,
      interval: interval,
      dueBefore: before.due,
      repsBefore: before.reps,
      lapsesBefore: before.lapses,
    ),
    FsrsActiveCard() => FsrsReviewLog(
      cardId: before.id,
      rating: rating,
      reviewedAt: reviewedAt,
      elapsed: elapsed,
      interval: interval,
      dueBefore: before.due,
      phaseBefore: before.phase,
      stepBefore: before.step,
      memoryBefore: before.memory,
      lastReviewBefore: before.lastReview,
      repsBefore: before.reps,
      lapsesBefore: before.lapses,
    ),
  };

  static Duration _elapsed(DateTime from, DateTime to) {
    final elapsed = to.difference(from);
    return elapsed.isNegative ? Duration.zero : elapsed;
  }

  static void _checkRetention(double value) {
    if (!(value > 0 && value < 1)) {
      throw ArgumentError.value(
        value,
        'desiredRetention',
        'must be between 0 and 1',
      );
    }
  }

  /// Depends only on [fuzzSeed] and the card, so preview and review agree.
  double _fuzzFactor(FsrsCard card) {
    var hash = 0x811c9dc5;
    for (final value in [
      fuzzSeed,
      card.id ?? 0,
      card.reps,
      card.due.microsecondsSinceEpoch,
    ]) {
      hash = ((hash ^ value) * 0x01000193) & 0x7fffffff;
    }
    return Random(hash).nextDouble();
  }

  /// Ordered so that hard <= good < easy.
  ({int again, int hard, int good, int easy}) _reviewDays(
    FsrsNextStates states,
    Duration elapsed,
    double fuzzFactor,
  ) {
    final elapsedDays = elapsed.inDays;
    int days(FsrsRating rating) =>
        _fuzzDays(toDays(states[rating].interval), elapsedDays, fuzzFactor);

    var hard = days(.hard);
    var good = days(.good);
    var easy = days(.easy);
    hard = min(hard, good);
    good = max(good, hard + 1);
    easy = max(easy, good + 1);
    return (
      again: days(.again),
      hard: hard.clamp(1, _maximumDays),
      good: good.clamp(1, _maximumDays),
      easy: easy.clamp(1, _maximumDays),
    );
  }

  int _fuzzDays(double interval, int elapsedDays, double fuzzFactor) {
    final maximum = _maximumDays;
    if (!enableFuzz || interval < 2.5 || maximum < 2) {
      return interval.round().clamp(1, maximum);
    }
    final bounded = min(interval, maximum.toDouble());
    var delta = 1.0;
    if (bounded > 2.5) delta += 0.15 * (min<double>(bounded, 7) - 2.5);
    if (bounded > 7.0) delta += 0.10 * (min<double>(bounded, 20) - 7.0);
    if (bounded > 20.0) delta += 0.05 * (bounded - 20.0);

    var low = (bounded - delta).round().clamp(2, maximum);
    final high = (bounded + delta).round().clamp(2, maximum);
    if (bounded > elapsedDays) low = max(low, elapsedDays + 1);
    low = min(low, high);
    return min(low + (fuzzFactor * (high - low + 1)).floor(), high);
  }
}

final class _Review {
  _Review(this.scheduler, this.card, DateTime? now, double? desiredRetention)
    : reviewedAt = (now ?? DateTime.now()).toUtc() {
    final retention = desiredRetention ?? scheduler.desiredRetention;
    FsrsScheduler._checkRetention(retention);
    final card = this.card;
    final (memory, elapsed) = switch (card) {
      FsrsNewCard() => (null, Duration.zero),
      FsrsActiveCard(:final memory, :final lastReview) => (
        memory,
        FsrsScheduler._elapsed(lastReview, reviewedAt),
      ),
    };
    this.elapsed = elapsed;
    states = scheduler.model.nextStates(
      memory,
      elapsed: elapsed,
      desiredRetention: retention,
    );
  }

  final FsrsScheduler scheduler;
  final FsrsCard card;
  final DateTime reviewedAt;
  late final Duration elapsed;
  late final FsrsNextStates states;

  late final ({int again, int hard, int good, int easy}) reviewDays = scheduler
      ._reviewDays(states, elapsed, scheduler._fuzzFactor(card));

  bool get _inReview =>
      card is FsrsActiveCard &&
      (card as FsrsActiveCard).phase == FsrsPhase.review;

  FsrsReviewResult apply(FsrsRating rating) {
    final card = this.card;
    final lapsed = _inReview && rating == FsrsRating.again;
    if (!scheduler.enableShortTerm) {
      return _graduate(rating, lapsed: lapsed);
    }
    return switch (card) {
      FsrsNewCard() => _step(rating, 0, scheduler.learningSteps, .learning),
      FsrsActiveCard(phase: .learning, :final step) => _step(
        rating,
        step,
        scheduler.learningSteps,
        .learning,
      ),
      FsrsActiveCard(phase: .relearning, :final step) => _step(
        rating,
        step,
        scheduler.relearningSteps,
        .relearning,
      ),
      FsrsActiveCard(phase: .review) =>
        lapsed && scheduler.relearningSteps.isNotEmpty
            ? _result(
                rating,
                phase: .relearning,
                step: 0,
                interval: scheduler.relearningSteps.first,
                lapsed: true,
              )
            : _graduate(rating, lapsed: lapsed),
    };
  }

  FsrsReviewResult _step(
    FsrsRating rating,
    int step,
    List<Duration> steps,
    FsrsPhase phase,
  ) {
    if (steps.isEmpty || (step >= steps.length && rating != .again)) {
      return _graduate(rating);
    }
    switch (rating) {
      case .again:
        return _result(rating, phase: phase, step: 0, interval: steps.first);
      case .hard:
        final interval = step != 0
            ? steps[min(step, steps.length - 1)]
            : steps.length == 1
            ? steps.first * 1.5
            : (steps[0] + steps[1]) ~/ 2;
        return _result(rating, phase: phase, step: step, interval: interval);
      case .good:
        if (step + 1 >= steps.length) return _graduate(rating);
        return _result(
          rating,
          phase: phase,
          step: step + 1,
          interval: steps[step + 1],
        );
      case .easy:
        return _graduate(rating);
    }
  }

  FsrsReviewResult _graduate(FsrsRating rating, {bool lapsed = false}) {
    final days = switch (rating) {
      .again => reviewDays.again,
      .hard => reviewDays.hard,
      .good => reviewDays.good,
      .easy => reviewDays.easy,
    };
    return _result(
      rating,
      phase: .review,
      step: 0,
      interval: Duration(days: days),
      lapsed: lapsed,
    );
  }

  FsrsReviewResult _result(
    FsrsRating rating, {
    required FsrsPhase phase,
    required int step,
    required Duration interval,
    bool lapsed = false,
  }) {
    final next = FsrsActiveCard(
      id: card.id,
      phase: phase,
      step: step,
      memory: states[rating].memory,
      due: reviewedAt.add(interval),
      lastReview: reviewedAt,
      reps: card.reps + 1,
      lapses: card.lapses + (lapsed ? 1 : 0),
    );
    return (
      card: next,
      log: FsrsScheduler._log(
        card,
        rating: rating,
        reviewedAt: reviewedAt,
        elapsed: elapsed,
        interval: interval,
      ),
    );
  }
}
