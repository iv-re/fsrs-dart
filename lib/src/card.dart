import 'package:fsrs_dart/src/memory_state.dart';
import 'package:meta/meta.dart';

enum FsrsPhase {
  learning,

  review,

  relearning,
}

@immutable
sealed class FsrsCard {
  const FsrsCard();

  factory FsrsCard.create({int? id, DateTime? now}) =>
      FsrsNewCard(id: id, due: now ?? DateTime.now());

  /// Also seeds interval fuzz.
  int? get id;

  /// UTC.
  DateTime get due;

  int get reps;

  /// Number of `again` answers in [FsrsPhase.review].
  int get lapses;
}

void _checkCount(int value, String name) {
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must not be negative');
  }
}

final class FsrsNewCard extends FsrsCard {
  /// [due] is converted to UTC. Throws [ArgumentError] if [reps] or [lapses]
  /// is negative.
  FsrsNewCard({
    required DateTime due,
    this.id,
    this.reps = 0,
    this.lapses = 0,
  }) : due = due.toUtc() {
    _checkCount(reps, 'reps');
    _checkCount(lapses, 'lapses');
  }

  @override
  final int? id;

  @override
  final DateTime due;

  @override
  final int reps;

  @override
  final int lapses;

  FsrsNewCard copyWith({int? id, DateTime? due, int? reps, int? lapses}) =>
      FsrsNewCard(
        id: id ?? this.id,
        due: due ?? this.due,
        reps: reps ?? this.reps,
        lapses: lapses ?? this.lapses,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsNewCard &&
          id == other.id &&
          due == other.due &&
          reps == other.reps &&
          lapses == other.lapses;

  @override
  int get hashCode => Object.hash(id, due, reps, lapses);

  @override
  String toString() =>
      'FsrsNewCard(id: $id, due: $due, reps: $reps, lapses: $lapses)';
}

final class FsrsActiveCard extends FsrsCard {
  /// [due] and [lastReview] are converted to UTC. Throws [ArgumentError] if
  /// [step], [reps] or [lapses] is negative, or [step] is not 0 in
  /// [FsrsPhase.review].
  FsrsActiveCard({
    required this.phase,
    required this.memory,
    required DateTime due,
    required DateTime lastReview,
    this.id,
    this.step = 0,
    this.reps = 0,
    this.lapses = 0,
  }) : due = due.toUtc(),
       lastReview = lastReview.toUtc() {
    _checkCount(step, 'step');
    _checkCount(reps, 'reps');
    _checkCount(lapses, 'lapses');
    if (phase == FsrsPhase.review && step != 0) {
      throw ArgumentError.value(step, 'step', 'must be 0 in the review phase');
    }
  }

  @override
  final int? id;

  @override
  final DateTime due;

  @override
  final int reps;

  @override
  final int lapses;

  final FsrsPhase phase;

  /// Always 0 in [FsrsPhase.review].
  final int step;

  final FsrsMemoryState memory;

  /// UTC.
  final DateTime lastReview;

  /// Returns a copy with the given fields replaced.
  FsrsActiveCard copyWith({
    int? id,
    DateTime? due,
    int? reps,
    int? lapses,
    FsrsPhase? phase,
    int? step,
    FsrsMemoryState? memory,
    DateTime? lastReview,
  }) => FsrsActiveCard(
    id: id ?? this.id,
    due: due ?? this.due,
    reps: reps ?? this.reps,
    lapses: lapses ?? this.lapses,
    phase: phase ?? this.phase,
    step: step ?? this.step,
    memory: memory ?? this.memory,
    lastReview: lastReview ?? this.lastReview,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsActiveCard &&
          id == other.id &&
          due == other.due &&
          reps == other.reps &&
          lapses == other.lapses &&
          phase == other.phase &&
          step == other.step &&
          memory == other.memory &&
          lastReview == other.lastReview;

  @override
  int get hashCode =>
      Object.hash(id, due, reps, lapses, phase, step, memory, lastReview);

  @override
  String toString() =>
      'FsrsActiveCard(id: $id, phase: ${phase.name}, step: $step, due: $due, '
      'reps: $reps, lapses: $lapses, memory: $memory, '
      'lastReview: $lastReview)';
}
