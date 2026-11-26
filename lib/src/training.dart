import 'package:fsrs_dart/src/rating.dart';
import 'package:meta/meta.dart';

@immutable
final class FsrsReview {
  /// Throws [ArgumentError] if [elapsed] is negative.
  FsrsReview(this.rating, this.elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
  }

  final FsrsRating rating;

  /// Time since the previous review; [Duration.zero] for the first review.
  final Duration elapsed;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsReview && rating == other.rating && elapsed == other.elapsed;

  @override
  int get hashCode => Object.hash(rating, elapsed);

  @override
  String toString() => 'FsrsReview($rating, $elapsed)';
}

/// The review history of one card up to the review being predicted.
@immutable
final class FsrsTrainingItem {
  /// Throws [ArgumentError] if [reviews] is empty or the first review has a
  /// non-zero [FsrsReview.elapsed].
  FsrsTrainingItem({required List<FsrsReview> reviews, this.cardId})
    : reviews = List.unmodifiable(reviews) {
    if (this.reviews.isEmpty) {
      throw ArgumentError.value(reviews, 'reviews', 'must not be empty');
    }
    if (this.reviews.first.elapsed != Duration.zero) {
      throw ArgumentError.value(
        reviews,
        'reviews',
        'the first review must have zero elapsed time',
      );
    }
  }

  final List<FsrsReview> reviews;

  /// Used by training only when every item of the set has one.
  final int? cardId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsrsTrainingItem ||
        cardId != other.cardId ||
        reviews.length != other.reviews.length) {
      return false;
    }
    for (var i = 0; i < reviews.length; i++) {
      if (reviews[i] != other.reviews[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(cardId, Object.hashAll(reviews));

  @override
  String toString() => 'FsrsTrainingItem(cardId: $cardId, reviews: $reviews)';
}

@immutable
final class const FsrsEvaluation({
  /// Binary cross-entropy of the predicted recall probabilities (lower is
  /// better).
  required final double logLoss,

  /// Calibration error across retrievability bins (lower is better).
  required final double rmseBins,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsEvaluation &&
          logLoss == other.logLoss &&
          rmseBins == other.rmseBins;

  @override
  int get hashCode => Object.hash(logLoss, rmseBins);

  @override
  String toString() => 'FsrsEvaluation(logLoss: $logLoss, rmseBins: $rmseBins)';
}
