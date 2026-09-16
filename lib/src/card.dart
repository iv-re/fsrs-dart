import 'package:fsrs_dart/src/card_state.dart';
import 'package:fsrs_dart/src/memory_state.dart';

/// Represents a flashcard tracked by the FSRS algorithm.
final class const FsrsCard({
  /// The timestamp when this card is due for its next review.
  required final DateTime due,

  /// Optional unique identifier of the card.
  final int? cardId,

  /// The current state of the card (newCard, learning, review, relearning).
  final FsrsCardState state = .newCard,

  /// Current step index within learning or relearning steps.
  final int step = 0,

  /// Total number of review repetitions completed.
  final int reps = 0,

  /// Number of times the card was forgotten (failed review in review state).
  final int lapses = 0,

  /// The current memory state of the card (null if brand-new).
  final FsrsMemoryState? memoryState,

  /// The timestamp of the most recent review (null if brand-new).
  final DateTime? lastReview,
}) {
  /// The stability of the memory state in days (null if never reviewed).
  double? get stability => memoryState?.stability;

  /// The difficulty of the card between 1.0 and 10.0 (null if never reviewed).
  double? get difficulty => memoryState?.difficulty;

  /// Whether the card has ever been reviewed.
  bool get isNew => state == FsrsCardState.newCard || memoryState == null;

  /// Returns a copy of this card with updated fields.
  FsrsCard copyWith({
    DateTime? due,
    int? cardId,
    FsrsCardState? state,
    int? step,
    int? reps,
    int? lapses,
    FsrsMemoryState? memoryState,
    DateTime? lastReview,
  }) {
    return FsrsCard(
      due: due ?? this.due,
      cardId: cardId ?? this.cardId,
      state: state ?? this.state,
      step: step ?? this.step,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      memoryState: memoryState ?? this.memoryState,
      lastReview: lastReview ?? this.lastReview,
    );
  }

  /// Returns a copy of this card with specified nullable fields reset to null.
  FsrsCard reset({
    bool memoryState = false,
    bool lastReview = false,
  }) {
    return FsrsCard(
      due: due,
      cardId: cardId,
      state: state,
      step: step,
      reps: reps,
      lapses: lapses,
      memoryState: memoryState ? null : this.memoryState,
      lastReview: lastReview ? null : this.lastReview,
    );
  }

  @override
  String toString() {
    return 'FsrsCard(cardId: $cardId, state: $state, step: $step, '
        'reps: $reps, lapses: $lapses, due: $due, memoryState: $memoryState, '
        'lastReview: $lastReview)';
  }
}
