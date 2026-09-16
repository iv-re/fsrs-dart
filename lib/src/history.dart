import 'package:fsrs_dart/src/card.dart';
import 'package:fsrs_dart/src/card_state.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:fsrs_dart/src/scheduling_result.dart';
import 'package:meta/meta.dart';

/// A historical review entry used for replaying scheduling in `reschedule`.
@immutable
final class const FsrsHistoryEntry({
  /// Timestamp when the review took place.
  required final DateTime review,

  /// Performance rating selected during the review.
  required final FsrsRating rating,

  /// Optional card state override (for manual rating).
  final FsrsCardState? state,

  /// Optional next due date override (for manual rating).
  final DateTime? due,

  /// Optional stability override (for manual rating).
  final double? stability,

  /// Optional difficulty override (for manual rating).
  final double? difficulty,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsHistoryEntry &&
          runtimeType == other.runtimeType &&
          review == other.review &&
          rating == other.rating &&
          state == other.state &&
          due == other.due &&
          stability == other.stability &&
          difficulty == other.difficulty;

  @override
  int get hashCode => Object.hash(
    review,
    rating,
    state,
    due,
    stability,
    difficulty,
  );

  @override
  String toString() => 'FsrsHistoryEntry(review: $review, rating: $rating)';
}

/// The result of rescheduling a card from its review history.
@immutable
final class const FsrsRescheduleResult({
  /// Collection of scheduling outcomes generated during the replay.
  required final List<FsrsRecordLogItem> collections,

  /// The final rescheduled card state.
  required final FsrsCard card,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsRescheduleResult &&
          runtimeType == other.runtimeType &&
          card == other.card;

  @override
  int get hashCode => card.hashCode;

  @override
  String toString() =>
      'FsrsRescheduleResult(collections: ${collections.length}, card: $card)';
}
