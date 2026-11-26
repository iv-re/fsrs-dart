import 'package:meta/meta.dart';

@immutable
final class FsrsMemoryState {
  /// [stabilityFast] defaults to [stability].
  ///
  /// Throws [ArgumentError] if a stability is not finite and positive or
  /// [difficulty] is not finite.
  FsrsMemoryState({
    required this.stability,
    required this.difficulty,
    double? stabilityFast,
  }) : stabilityFast = stabilityFast ?? stability {
    _checkStability(stability, 'stability');
    _checkStability(this.stabilityFast, 'stabilityFast');
    if (!difficulty.isFinite) {
      throw ArgumentError.value(difficulty, 'difficulty', 'must be finite');
    }
  }

  /// Days until the probability of recall drops to 90%.
  final double stability;

  /// How hard the item is, from 1 (easiest) to 10 (hardest).
  final double difficulty;

  /// The fast stability trace of FSRS-7. Equals [stability] under FSRS-6.
  final double stabilityFast;

  static void _checkStability(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(value, name, 'must be finite and positive');
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsMemoryState &&
          stability == other.stability &&
          difficulty == other.difficulty &&
          stabilityFast == other.stabilityFast;

  @override
  int get hashCode => Object.hash(stability, difficulty, stabilityFast);

  @override
  String toString() =>
      'FsrsMemoryState(stability: $stability, difficulty: $difficulty, '
      'stabilityFast: $stabilityFast)';
}
