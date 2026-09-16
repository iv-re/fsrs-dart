/// The scheduling state of a card in the spaced repetition workflow.
enum const FsrsCardState(final int value) {
  /// Never reviewed card.
  newCard(0),

  /// Card undergoing initial learning steps.
  learning(1),

  /// Card that has graduated into regular FSRS daily spaced repetition.
  review(2),

  /// Previously learned card forgotten on review and undergoing relearning.
  relearning(3),
}
