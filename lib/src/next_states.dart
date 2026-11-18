import 'package:fsrs_dart/src/item_state.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:meta/meta.dart';

/// The calculated next states for each of the four possible review ratings.
@immutable
final class const FsrsNextStates({
  /// The next state if the user chooses 'Again'.
  required final FsrsItemState again,

  /// The next state if the user chooses 'Hard'.
  required final FsrsItemState hard,

  /// The next state if the user chooses 'Good'.
  required final FsrsItemState good,

  /// The next state if the user chooses 'Easy'.
  required final FsrsItemState easy,
}) {
  /// Access the next state corresponding to [rating].
  FsrsItemState operator [](FsrsRating rating) => switch (rating) {
    FsrsRating.again => again,
    FsrsRating.hard => hard,
    FsrsRating.good => good,
    FsrsRating.easy => easy,
    FsrsRating.manual => throw ArgumentError(
      'No next state for manual rating',
    ),
  };

  /// Returns the next state for [rating].
  FsrsItemState get(FsrsRating rating) => this[rating];

  /// Returns a map of all states keyed by [FsrsRating].
  Map<FsrsRating, FsrsItemState> toMap() => {
    FsrsRating.again: again,
    FsrsRating.hard: hard,
    FsrsRating.good: good,
    FsrsRating.easy: easy,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsNextStates &&
          runtimeType == other.runtimeType &&
          again == other.again &&
          hard == other.hard &&
          good == other.good &&
          easy == other.easy;

  @override
  int get hashCode => Object.hash(again, hard, good, easy);

  @override
  String toString() =>
      'FsrsNextStates(again: $again, hard: $hard, good: $good, easy: $easy)';
}
