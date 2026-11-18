import 'package:fsrs_dart/src/card.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:fsrs_dart/src/review_log.dart';
import 'package:meta/meta.dart';

/// The outcome of reviewing an [FsrsCard], containing the updated card
/// and the review log entry.
@immutable
final class const FsrsRecordLogItem({
  /// The updated card after applying the review.
  required final FsrsCard card,

  /// The review log entry representing this review event.
  required final FsrsReviewLog log,
}) {
  /// The rating applied in this review.
  FsrsRating get rating => log.rating;

  /// The scheduled interval until next review.
  Duration get interval => log.interval;

  /// The scheduled interval in whole days.
  int get scheduledDays => log.scheduledDays;

  /// The timestamp when this review was recorded.
  DateTime get reviewedAt => log.reviewedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsRecordLogItem &&
          runtimeType == other.runtimeType &&
          card == other.card &&
          log == other.log;

  @override
  int get hashCode => Object.hash(card, log);

  @override
  String toString() {
    return 'FsrsRecordLogItem(card: $card, log: $log)';
  }
}

/// Convenience alias matching FsrsScheduler terminology.
typedef FsrsSchedulingResult = FsrsRecordLogItem;

/// Map of scheduling outcomes for each review rating.
typedef FsrsRecordLog = Map<FsrsRating, FsrsRecordLogItem>;
