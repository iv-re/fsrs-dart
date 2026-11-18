import 'package:fsrs_dart/src/card_state.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:meta/meta.dart';

/// Represents a single review log entry recorded after reviewing a card.
///
/// The [state], [due], [step], [stability], [difficulty], and [lastReview]
/// fields capture the card's snapshot *before* this review was applied
/// (enabling lossless `rollback`), while [rating], [interval], [reviewedAt],
/// and [elapsedDays] describe the review event itself.
@immutable
final class const FsrsReviewLog({
  /// The rating assigned during this review.
  required final FsrsRating rating,

  /// The card state before this review was applied.
  required final FsrsCardState state,

  /// The card's scheduled due date before this review was applied.
  required final DateTime due,

  /// The stability of the card before this review (0 if brand-new).
  required final double stability,

  /// The difficulty of the card before this review (0 if brand-new).
  required final double difficulty,

  /// The scheduled interval until the next review.
  required final Duration interval,

  /// The timestamp when the review took place.
  required final DateTime reviewedAt,

  /// The number of days elapsed since the prior review (0 if first review).
  final int elapsedDays = 0,

  /// The card's learning/relearning step index before this review.
  final int step = 0,

  /// The card's previous review timestamp before this review (null if new).
  final DateTime? lastReview,
}) {
  /// The scheduled interval in whole days.
  int get scheduledDays => interval.inDays;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsReviewLog &&
          runtimeType == other.runtimeType &&
          rating == other.rating &&
          state == other.state &&
          due == other.due &&
          stability == other.stability &&
          difficulty == other.difficulty &&
          interval == other.interval &&
          reviewedAt == other.reviewedAt &&
          elapsedDays == other.elapsedDays &&
          step == other.step &&
          lastReview == other.lastReview;

  @override
  int get hashCode => Object.hash(
    rating,
    state,
    due,
    stability,
    difficulty,
    interval,
    reviewedAt,
    elapsedDays,
    step,
    lastReview,
  );

  @override
  String toString() {
    return 'FsrsReviewLog(rating: $rating, state: $state, due: $due, '
        'step: $step, stability: $stability, difficulty: $difficulty, '
        'interval: $interval, reviewedAt: $reviewedAt, '
        'elapsedDays: $elapsedDays, lastReview: $lastReview)';
  }
}
