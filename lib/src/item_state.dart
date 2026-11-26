import 'package:fsrs_dart/src/memory_state.dart';
import 'package:meta/meta.dart';

@immutable
final class const FsrsItemState({
  required final FsrsMemoryState memory,

  /// Before learning steps, fuzz and maximum interval are applied.
  required final Duration interval,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsItemState &&
          memory == other.memory &&
          interval == other.interval;

  @override
  int get hashCode => Object.hash(memory, interval);

  @override
  String toString() => 'FsrsItemState(memory: $memory, interval: $interval)';
}
