import 'package:fsrs_dart/src/item_state.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:meta/meta.dart';

@immutable
final class const FsrsNextStates({
  required final FsrsItemState again,
  required final FsrsItemState hard,
  required final FsrsItemState good,
  required final FsrsItemState easy,
}) {
  FsrsItemState operator [](FsrsRating rating) => switch (rating) {
    .again => again,
    .hard => hard,
    .good => good,
    .easy => easy,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsNextStates &&
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
