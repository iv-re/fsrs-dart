import 'package:meta/meta.dart';

/// Represents the memory state of an item in the FSRS system.
@immutable
final class const FsrsMemoryState({
  /// The stability of the memory state (in days).
  required final double stability,

  /// The difficulty of the item (typically 1.0 to 10.0).
  required final double difficulty,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsMemoryState &&
          runtimeType == other.runtimeType &&
          stability == other.stability &&
          difficulty == other.difficulty;

  @override
  int get hashCode => Object.hash(stability, difficulty);

  @override
  String toString() =>
      'FsrsMemoryState(stability: $stability, difficulty: $difficulty)';
}
