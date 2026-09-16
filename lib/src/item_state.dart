import 'package:fsrs_dart/src/memory_state.dart';
import 'package:meta/meta.dart';

/// Represents the next state of an item for a given rating.
@immutable
final class const FsrsItemState({
  /// The memory state of the item after this review.
  required final FsrsMemoryState memory,

  /// The scheduled interval (in days) until the next review.
  required final double interval,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsItemState &&
          runtimeType == other.runtimeType &&
          memory == other.memory &&
          interval == other.interval;

  @override
  int get hashCode => Object.hash(memory, interval);

  @override
  String toString() => 'FsrsItemState(memory: $memory, interval: $interval)';
}
