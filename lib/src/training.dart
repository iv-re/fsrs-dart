import 'package:fsrs_dart/src/rating.dart';
import 'package:meta/meta.dart';

/// A single review log entry for card training/optimization.
@immutable
final class const FsrsReview({
  /// The user rating given during this review.
  required final FsrsRating rating,

  /// The number of days elapsed since the previous review (0 for first review).
  required final int deltaT,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsReview &&
          runtimeType == other.runtimeType &&
          rating == other.rating &&
          deltaT == other.deltaT;

  @override
  int get hashCode => Object.hash(rating, deltaT);

  @override
  String toString() => 'FsrsReview(rating: $rating, deltaT: $deltaT)';
}

/// A complete review history for a single card used for training.
@immutable
final class const FsrsItem({
  /// Chronological sequence of reviews for this card.
  required final List<FsrsReview> reviews,
}) {
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsrsItem || runtimeType != other.runtimeType) return false;
    if (reviews.length != other.reviews.length) return false;
    for (var i = 0; i < reviews.length; i++) {
      if (reviews[i] != other.reviews[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(reviews);

  @override
  String toString() => 'FsrsItem(reviews: $reviews)';
}
