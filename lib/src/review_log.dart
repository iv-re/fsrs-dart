import 'package:fsrs_dart/src/card_state.dart';
import 'package:fsrs_dart/src/rating.dart';

/// Represents a single review log entry recorded after reviewing a card.
final class const FsrsReviewLog({
  /// The rating assigned during this review.
  required final FsrsRating rating,

  /// The card state before this review was applied.
  required final FsrsCardState state,

  /// The scheduled due date resulting from this review.
  required final DateTime due,

  /// The stability of the card resulting from this review.
  required final double stability,

  /// The difficulty of the card resulting from this review.
  required final double difficulty,

  /// The scheduled interval until the next review.
  required final Duration interval,

  /// The timestamp when the review took place.
  required final DateTime reviewedAt,

  /// The number of days elapsed since the prior review (0 if first review).
  final int elapsedDays = 0,
}) {
  /// The scheduled interval in whole days.
  int get scheduledDays => interval.inDays;

  @override
  String toString() {
    return 'FsrsReviewLog(rating: $rating, state: $state, due: $due, '
        'stability: $stability, difficulty: $difficulty, interval: $interval)';
  }
}
