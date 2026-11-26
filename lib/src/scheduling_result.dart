import 'package:fsrs_dart/src/card.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:fsrs_dart/src/review_log.dart';
import 'package:meta/meta.dart';

typedef FsrsReviewResult = ({FsrsCard card, FsrsReviewLog log});

/// Each entry equals what `FsrsScheduler.review` returns for that rating at
/// the same time, including fuzz.
@immutable
final class const FsrsPreview({
  required final FsrsReviewResult again,
  required final FsrsReviewResult hard,
  required final FsrsReviewResult good,
  required final FsrsReviewResult easy,
}) {
  FsrsReviewResult operator [](FsrsRating rating) => switch (rating) {
    .again => again,
    .hard => hard,
    .good => good,
    .easy => easy,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsPreview &&
          again == other.again &&
          hard == other.hard &&
          good == other.good &&
          easy == other.easy;

  @override
  int get hashCode => Object.hash(again, hard, good, easy);

  @override
  String toString() =>
      'FsrsPreview(again: $again, hard: $hard, good: $good, easy: $easy)';
}

@immutable
final class FsrsRescheduleResult {
  FsrsRescheduleResult({required this.card, required List<FsrsReviewLog> logs})
    : logs = List.unmodifiable(logs);

  final FsrsCard card;

  /// In chronological order.
  final List<FsrsReviewLog> logs;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsrsRescheduleResult ||
        card != other.card ||
        logs.length != other.logs.length) {
      return false;
    }
    for (var i = 0; i < logs.length; i++) {
      if (logs[i] != other.logs[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(card, Object.hashAll(logs));

  @override
  String toString() =>
      'FsrsRescheduleResult(card: $card, logs: ${logs.length})';
}
