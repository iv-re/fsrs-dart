# fsrs_dart

Free Spaced Repetition Scheduler (FSRS-6) for Dart.

## Installation

```yaml
dependencies:
  fsrs_dart: ^0.2.0
```

## Quick Start

```dart
import 'package:fsrs_dart/fsrs_dart.dart';

void main() {
  final fsrs = Fsrs();
  final now = DateTime.now().toUtc();

  // Create a new card
  final card = fsrs.createEmptyCard(now: now);

  // Preview scheduled intervals for all ratings
  final preview = fsrs.repeat(card, now: now);
  for (final entry in preview.entries) {
    print('${entry.key.name}: due in ${entry.value.interval}');
  }

  // Apply user rating (Again, Hard, Good, Easy)
  final result = fsrs.next(card, FsrsRating.good, now: now);
  print('Next due: ${result.card.due}');
  print('Stability: ${result.card.stability}');
}
```

## Usage

### Configuration

```dart
final fsrs = Fsrs(
  desiredRetention: 0.9,
  maximumInterval: 36500,
  enableShortTerm: true,
  enableFuzz: true,
  learningSteps: [
    Duration(minutes: 1),
    Duration(minutes: 10),
  ],
  relearningSteps: [
    Duration(minutes: 10),
  ],
);
```

### Review Log & Rollback

```dart
// Apply a review step
final result = fsrs.next(card, FsrsRating.good, now: now);

// Revert last review
final revertedCard = fsrs.rollback(result.card, result.log);

// Reset card to unlearned state
final forgotten = fsrs.forget(result.card, resetCount: true);
```

### Probability of Recall (`getRetrievability`)

```dart
final r = fsrs.getRetrievability(card, now: DateTime.now().toUtc());
print('Retrievability: $r'); // 0.0 .. 1.0
```

### Replay History (`reschedule`)

Reconstructs card state by sequentially replaying historical reviews:

```dart
final history = [
  FsrsHistoryEntry(
    review: DateTime.utc(2026, 1, 1),
    rating: FsrsRating.good,
  ),
  FsrsHistoryEntry(
    review: DateTime.utc(2026, 1, 5),
    rating: FsrsRating.good,
  ),
];

final initialCard = fsrs.createEmptyCard();
final result = fsrs.reschedule(initialCard, history);

print('Reps: ${result.card.reps}');
print('Due: ${result.card.due}');
```

### Parameter Optimization & Evaluation

Train custom 21-parameter weights on review logs:

```dart
final trainSet = [
  FsrsItem(
    reviews: [
      FsrsReview(rating: FsrsRating.good, deltaT: 0),
      FsrsReview(rating: FsrsRating.good, deltaT: 3),
      FsrsReview(rating: FsrsRating.easy, deltaT: 10),
    ],
  ),
];

// Optimize parameters
final customParameters = fsrs.computeParameters(
  trainSet,
  enableShortTerm: true,
  numRelearningSteps: 1,
);

// Evaluate accuracy (Log Loss & RMSE)
final evaluation = fsrs.evaluate(trainSet);
print('Log Loss: ${evaluation.logLoss}');
print('RMSE: ${evaluation.rmseBins}');

// Initialize scheduler with trained parameters
final optimizedFsrs = Fsrs(parameters: customParameters);
```
