import 'package:fsrs_dart/src/card.dart';
import 'package:fsrs_dart/src/memory_state.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:meta/meta.dart';

/// The `...Before` fields hold the card as it was before the event.
@immutable
final class FsrsReviewLog {
  /// Timestamps are converted to UTC. Throws [ArgumentError] if
  /// [phaseBefore] is set without [memoryBefore] and [lastReviewBefore], or a
  /// duration or count is negative.
  FsrsReviewLog({
    required DateTime reviewedAt,
    required this.interval,
    required DateTime dueBefore,
    this.cardId,
    this.rating,
    this.elapsed = Duration.zero,
    this.phaseBefore,
    this.stepBefore = 0,
    this.memoryBefore,
    DateTime? lastReviewBefore,
    this.repsBefore = 0,
    this.lapsesBefore = 0,
  }) : reviewedAt = reviewedAt.toUtc(),
       dueBefore = dueBefore.toUtc(),
       lastReviewBefore = lastReviewBefore?.toUtc() {
    if (phaseBefore != null &&
        (memoryBefore == null || this.lastReviewBefore == null)) {
      throw ArgumentError(
        'An active card (phaseBefore != null) needs memoryBefore and '
        'lastReviewBefore.',
      );
    }
    if (interval.isNegative) {
      throw ArgumentError.value(interval, 'interval', 'must not be negative');
    }
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
    for (final (value, name) in [
      (stepBefore, 'stepBefore'),
      (repsBefore, 'repsBefore'),
      (lapsesBefore, 'lapsesBefore'),
    ]) {
      if (value < 0) {
        throw ArgumentError.value(value, name, 'must not be negative');
      }
    }
  }

  final int? cardId;

  /// `null` for a manual change (forget, manual reschedule entry).
  final FsrsRating? rating;

  /// UTC.
  final DateTime reviewedAt;

  /// Zero for the first review.
  final Duration elapsed;

  final Duration interval;

  /// `null` if the card was new.
  final FsrsPhase? phaseBefore;

  final int stepBefore;

  /// UTC.
  final DateTime dueBefore;

  /// `null` if the card was new.
  final FsrsMemoryState? memoryBefore;

  /// `null` if the card was new.
  final DateTime? lastReviewBefore;

  final int repsBefore;

  final int lapsesBefore;

  FsrsCard get cardBefore {
    final phase = phaseBefore;
    if (phase == null) {
      return FsrsNewCard(
        id: cardId,
        due: dueBefore,
        reps: repsBefore,
        lapses: lapsesBefore,
      );
    }
    return FsrsActiveCard(
      id: cardId,
      phase: phase,
      step: stepBefore,
      memory: memoryBefore!,
      due: dueBefore,
      lastReview: lastReviewBefore!,
      reps: repsBefore,
      lapses: lapsesBefore,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsReviewLog &&
          cardId == other.cardId &&
          rating == other.rating &&
          reviewedAt == other.reviewedAt &&
          elapsed == other.elapsed &&
          interval == other.interval &&
          phaseBefore == other.phaseBefore &&
          stepBefore == other.stepBefore &&
          dueBefore == other.dueBefore &&
          memoryBefore == other.memoryBefore &&
          lastReviewBefore == other.lastReviewBefore &&
          repsBefore == other.repsBefore &&
          lapsesBefore == other.lapsesBefore;

  @override
  int get hashCode => Object.hash(
    cardId,
    rating,
    reviewedAt,
    elapsed,
    interval,
    phaseBefore,
    stepBefore,
    dueBefore,
    memoryBefore,
    lastReviewBefore,
    repsBefore,
    lapsesBefore,
  );

  @override
  String toString() =>
      'FsrsReviewLog(cardId: $cardId, rating: ${rating?.name}, '
      'reviewedAt: $reviewedAt, elapsed: $elapsed, interval: $interval, '
      'before: ${phaseBefore?.name ?? 'new'})';
}
