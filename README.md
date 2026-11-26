# fsrs_dart

Free Spaced Repetition Scheduler (FSRS-7 and FSRS-6) for Dart and Flutter,
powered by the Rust [fsrs-rs](https://github.com/open-spaced-repetition/fsrs-rs)
engine via FFI.

## Installation

```yaml
dependencies:
  fsrs_dart: ^0.3.0
```

Prebuilt binaries cover Android, iOS, macOS, Linux and Windows. Elsewhere the
Rust sources are compiled, which requires a Rust toolchain.

## Quick start

```dart
import 'package:fsrs_dart/fsrs_dart.dart';

void main() {
  final scheduler = FsrsScheduler();
  final now = DateTime.now().toUtc();

  final card = FsrsCard.create(now: now);

  final preview = scheduler.preview(card, now: now);
  for (final rating in FsrsRating.values) {
    print('${rating.name}: due in ${preview[rating].log.interval}');
  }

  final result = scheduler.review(card, FsrsRating.good, now: now);
  print('Due: ${result.card.due}');
}
```

## API

- `FsrsModel`: the memory model (parameters).
- `FsrsScheduler`: due dates, learning steps, fuzz.
- `FsrsOptimizer`: trains parameters on review logs.

A card is either `FsrsNewCard` or `FsrsActiveCard`:

```dart
switch (card) {
  case FsrsNewCard():
    print('New');
  case FsrsActiveCard(:final phase, :final memory):
    print('${phase.name}, stability ${memory.stability} days');
}
```

## Scheduling

```dart
final scheduler = FsrsScheduler(
  model: FsrsModel(),
  desiredRetention: 0.9,
  learningSteps: const [Duration(minutes: 1), Duration(minutes: 10)],
  relearningSteps: const [Duration(minutes: 10)],
  maximumInterval: const Duration(days: 36500),
  enableShortTerm: true,
  enableFuzz: true,
);

scheduler.review(card, FsrsRating.good, desiredRetention: 0.85);

final recall = scheduler.retrievability(card); // null for a new card
```

### Undo and forget

```dart
final (:card, :log) = scheduler.review(previous, FsrsRating.again);
final restored = scheduler.undo(card, log); // == previous

final reset = scheduler.forget(card, resetCounts: true);
```

### Replaying history

```dart
final result = scheduler.reschedule(card, [
  FsrsHistoryEntry.review(DateTime.utc(2026, 1, 1), FsrsRating.good),
  FsrsHistoryEntry.review(DateTime.utc(2026, 1, 5), FsrsRating.good),
  FsrsHistoryEntry.manual(
    DateTime.utc(2026, 1, 6),
    due: DateTime.utc(2026, 1, 20),
  ),
]);
```

## Optimizing parameters

```dart
final items = FsrsOptimizer.itemsFromLogs(allLogs);
final trained = await FsrsOptimizer.computeParameters(items);

if (trained == FsrsModel.defaults(FsrsVersion.v7)) {
  print('Not enough reviews yet.');
}

final evaluation = await trained.evaluate(items);
print('Log loss: ${evaluation.logLoss}, RMSE: ${evaluation.rmseBins}');

save(trained.parameters);
final scheduler = FsrsScheduler(model: FsrsModel(parameters: load()));
```

`itemsFromLogs` requires a `cardId` in every log, so create cards with
`FsrsCard.create(id: ...)`.

## FSRS-6

21 parameters (or legacy 17 and 19) select FSRS-6:

```dart
final model = FsrsModel(parameters: savedWeights);
print(model.version); // FsrsVersion.v6
```

To train FSRS-6, pass `version: FsrsVersion.v6` to `computeParameters`.

## Using the model directly

```dart
final model = FsrsModel();
final states = model.nextStates(
  memory, // null for a new card
  elapsed: const Duration(hours: 30),
  desiredRetention: 0.9,
);

final memory = model.memoryStateFromHistory([
  FsrsReview(FsrsRating.good, Duration.zero),
  FsrsReview(FsrsRating.hard, const Duration(days: 3)),
]);

final imported = model.memoryStateFromSm2(
  easeFactor: 2.5,
  interval: const Duration(days: 30),
  sm2Retention: 0.9,
);
```

## Migrating from 0.2

See the [changelog](CHANGELOG.md#030).
