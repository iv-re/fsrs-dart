## 0.3.0

- Engine upgraded to fsrs-rs 7.0.0; FSRS-7 is the default model.

### Breaking changes

| 0.2 | 0.3 |
|---|---|
| `Fsrs(parameters: ..., desiredRetention: ..., ...)` | `FsrsScheduler(model: FsrsModel(parameters: ...), desiredRetention: ..., ...)` |
| `fsrs.close()` | Not needed: native resources are released automatically |
| `fsrs.createEmptyCard(now: ...)` | `FsrsCard.create(now: ...)` |
| `fsrs.repeat(card)` → `Map` | `scheduler.preview(card)` → `FsrsPreview` |
| `fsrs.next(card, rating)` | `scheduler.review(card, rating)` → `(card:, log:)` |
| `fsrs.rollback(card, log)` | `scheduler.undo(card, log)` |
| `fsrs.forget(card, resetCount: ...)` | `scheduler.forget(card, resetCounts: ...)` |
| `fsrs.getRetrievability(card)` → `0` for a new card | `scheduler.retrievability(card)` → `null` for a new card |
| `fsrs.reschedule(card, entries, skipManual: ...)` | `scheduler.reschedule(card, entries)` |
| `fsrs.nextStates(memoryState:, daysElapsed: int)` | `model.nextStates(memory, elapsed: Duration, desiredRetention:)` |
| `fsrs.currentRetrievability(..., decay:)` | `model.retrievability(memory, elapsed)` |
| `fsrs.computeParameters(items)` → `List<double>` | `await FsrsOptimizer.computeParameters(items)` → `FsrsModel` |
| `fsrs.evaluate(items)` | `await model.evaluate(items)` |
| `Fsrs.defaultParameters`, `Fsrs.defaultDecay`, `fsrs.decay` | `FsrsVersion.v7.defaultParameters`; decay is no longer exposed |
| `FsrsRating.manual`, `isGrade` | Removed: manual events have `log.rating == null` |
| `FsrsCard` with `state` and nullable `memoryState` | Sealed `FsrsNewCard` / `FsrsActiveCard(phase:, memory:, ...)` |
| `FsrsCardState` | `FsrsPhase` (`learning`, `review`, `relearning`); new cards are `FsrsNewCard` |
| `FsrsReviewLog.state/stability/difficulty/step/due/lastReview` | `phaseBefore`, `memoryBefore`, `stepBefore`, `dueBefore`, `lastReviewBefore`, plus `repsBefore`, `lapsesBefore`, `cardId`, `elapsed` |
| `FsrsReviewLog.elapsedDays: int`, `scheduledDays` | `elapsed: Duration`, `interval: Duration` |
| `FsrsHistoryEntry(review:, rating:, ...)` | `FsrsHistoryEntry.review(at, rating)` / `.manual(at, due:, phase:, memory:)` |
| `FsrsItem`, `FsrsReview(rating:, deltaT: int)` | `FsrsTrainingItem(reviews:, cardId:)`, `FsrsReview(rating, Duration)` |
| `FsrsModelEvaluation` | `FsrsEvaluation` |
| `FsrsRecordLog`, `FsrsRecordLogItem`, `FsrsSchedulingResult` | `FsrsPreview`, `FsrsReviewResult` |
| `FsrsItemState.interval: double` (days) | `Duration` |
| `FsrsException` | Sealed: `FsrsInvalidParametersException`, `FsrsNotEnoughDataException`, `FsrsNativeException` |
| `Random? random` option | `int fuzzSeed` |
| `maximumInterval: int` (days) | `Duration` |

- `FsrsMemoryState` gains `stabilityFast`, defaulting to `stability`.
- **Breaking (FFI ABI)**: native functions return a status code and take time
  in fractional days; decay functions are removed.

### Behavior changes

- `FsrsModel()` and `FsrsScheduler()` use FSRS-7. Pass 21 parameters (or
  `FsrsModel.defaults(FsrsVersion.v6)`) to keep FSRS-6.
- Elapsed time is passed to the model exactly instead of being truncated to
  whole days. FSRS-7 uses the fraction; FSRS-6 rounds it to the nearest day,
  so a review 12 hours or more after the last one counts as one day, not
  zero.
- Interval fuzz is deterministic per card: `preview` and `review` now return
  the same interval. Review-phase intervals are ordered hard <= good < easy.
- Manual entries in `reschedule` no longer increment `reps`.
- `undo` restores `reps` and `lapses` exactly, including after
  `forget(resetCounts: true)`.
- With too little data, `computeParameters` returns the default model of the
  requested version.

### New

- `FsrsModel.version`, `memoryStateFromHistory`, `memoryStateFromSm2`,
  `interval`.
- `FsrsOptimizer.itemsFromLogs` builds training data from scheduler logs.
- Training and evaluation pass card ids to the engine and run in a background
  isolate.
- `FsrsModel` can be sent to other isolates.

## 0.2.0

- **Breaking**: `FsrsReviewLog.stability` and `FsrsReviewLog.difficulty` now record pre-review values (matching `due`, `state`, and `ts-fsrs`) and include `step` and `lastReview` for lossless `rollback`.
- **Breaking (FFI ABI)**: Simplified native FFI surface (`fsrs_next_states` and `fsrs_compute_parameters` now write into caller-allocated buffers; added `fsrs_decay`; removed unused C exports).
- Fixed allocator layout mismatch UB in `fsrs_parameters_free` and null/empty slice safety in Rust FFI.
- Fixed `Fsrs` constructor native memory leak when scheduler argument validation fails.
- Fixed `rollback` to restore `memoryState`, `lastReview`, and `step` across all card states.
- Fixed `forget` to reset `step` to `0` and `lastReview` to `null`.
- Fixed `enableShortTerm: false` not incrementing `lapses` on `FsrsRating.again` for review cards.
- Fixed `_applyFuzz` throwing `ArgumentError` when `maximumInterval == 1`, and avoided unnecessary RNG draws in `reviewCard`.
- Fixed `getRetrievability` / `currentRetrievability` to use the model's configured `decay` parameter and fractional elapsed days.
- Fixed `reschedule` manual entries to preserve sub-day intervals and reset `step` appropriately.
- Fixed `FsrsRescheduleResult.==` and added `@immutable`, `==`, and `hashCode` to all model classes.
- Fixed `hook/build.dart` prebuilt cache collision across architectures (e.g. iOS Simulator arm64/x64), added hook dependency tracking, timeouts, and temp-file cleanup.
- Fixed `src/build.rs` to avoid rewriting `fsrs_dart.h` when unchanged, and excluded `src/rust-toolchain.toml` from published archives.
- Moved `logging` to `dev_dependencies` and added CI workflow.

## 0.1.0

- Initial release.
