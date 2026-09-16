import 'package:fsrs_dart/src/rating.dart';

/// A single review log entry for card training/optimization.
final class const FsrsReview({
  /// The user rating given during this review.
  required final FsrsRating rating,

  /// The number of days elapsed since the previous review (0 for first review).
  required final int deltaT,
}) {
  @override
  String toString() => 'FsrsReview(rating: $rating, deltaT: $deltaT)';
}

/// A complete review history for a single card used for training.
final class const FsrsItem({
  /// Chronological sequence of reviews for this card.
  required final List<FsrsReview> reviews,
}) {
  @override
  String toString() => 'FsrsItem(reviews: $reviews)';
}
