import 'dart:math';

import 'package:checks/checks.dart';
import 'package:fsrs_dart/fsrs_dart.dart';
import 'package:test/scaffolding.dart';

void main() {
  group('Fsrs FFI Core', () {
    late Fsrs fsrs;

    setUp(() {
      fsrs = Fsrs();
    });

    tearDown(() {
      fsrs.close();
    });

    test('exposes default parameters and decay', () {
      final params = Fsrs.defaultParameters;
      check(params).length.equals(21);
      check(params.first).isGreaterThan(0.0);

      final decay = Fsrs.defaultDecay;
      check(decay)
        ..isGreaterOrEqual(0.1542 - 0.0001)
        ..isLessOrEqual(0.1542 + 0.0001);
      check(fsrs.decay).equals(decay);
    });

    test('uses custom model decay for retrievability', () {
      final customParams = List<double>.of(Fsrs.defaultParameters)..[20] = 0.5;
      final customFsrs = Fsrs(parameters: customParams);
      addTearDown(customFsrs.close);

      check(customFsrs.decay)
        ..isGreaterOrEqual(0.5 - 0.0001)
        ..isLessOrEqual(0.5 + 0.0001);

      const memory = FsrsMemoryState(stability: 10, difficulty: 5);
      final rDefault = fsrs.currentRetrievability(
        memoryState: memory,
        daysElapsed: 30,
      );
      final rCustom = customFsrs.currentRetrievability(
        memoryState: memory,
        daysElapsed: 30,
      );
      check(rCustom).not((it) => it.equals(rDefault));

      // FSRS-5 (19 params) fills decay with 0.5
      final fsrs5 = Fsrs(parameters: Fsrs.defaultParameters.sublist(0, 19));
      addTearDown(fsrs5.close);
      check(fsrs5.decay)
        ..isGreaterOrEqual(0.5 - 0.0001)
        ..isLessOrEqual(0.5 + 0.0001);
    });

    test('schedules new card with nextStates', () {
      final states = fsrs.nextStates();

      check(states.again.interval).isGreaterOrEqual(0.0);
      check(states.hard.interval).isGreaterThan(0.0);
      check(states.good.interval).isGreaterThan(states.hard.interval);
      check(states.easy.interval).isGreaterThan(states.good.interval);

      check(states.good.memory.stability).isGreaterThan(0.0);
      check(states.good.memory.difficulty).isGreaterThan(0.0);

      // Test operator []
      check(states[FsrsRating.again]).equals(states.again);
      check(states[FsrsRating.good]).equals(states.good);
    });

    test('schedules existing card', () {
      const initialMemory = FsrsMemoryState(stability: 7, difficulty: 5);
      final states = fsrs.nextStates(
        memoryState: initialMemory,
        daysElapsed: 7,
      );

      check(
        states.good.memory.stability,
      ).isGreaterThan(initialMemory.stability);
      check(states.good.interval).isGreaterThan(0.0);
    });

    test('computes nextState directly for a rating', () {
      final state = fsrs.nextState(rating: FsrsRating.good);
      check(state.memory.stability).isGreaterThan(0.0);
      check(state.interval).isGreaterThan(0.0);
    });

    test('calculates retrievability correctly', () {
      const memory = FsrsMemoryState(stability: 10, difficulty: 5);
      final r0 = fsrs.currentRetrievability(
        memoryState: memory,
        daysElapsed: 0,
      );
      check(r0)
        ..isGreaterOrEqual(1.0 - 0.001)
        ..isLessOrEqual(1.0 + 0.001);

      final r10 = fsrs.currentRetrievability(
        memoryState: memory,
        daysElapsed: 10,
      );
      check(r10)
        ..isGreaterOrEqual(0.9 - 0.05)
        ..isLessOrEqual(0.9 + 0.05);
      check(r10).isLessThan(r0);
    });

    test('validates arguments and handles invalid constructor options', () {
      check(() => Fsrs(desiredRetention: 0)).throws<ArgumentError>();
      check(() => Fsrs(desiredRetention: 1)).throws<ArgumentError>();
      check(() => Fsrs(maximumInterval: 0)).throws<ArgumentError>();

      check(() => fsrs.nextStates(daysElapsed: -1)).throws<ArgumentError>();
      check(
        () => fsrs.currentRetrievability(
          memoryState: const FsrsMemoryState(stability: 5, difficulty: 5),
          daysElapsed: -0.5,
        ),
      ).throws<ArgumentError>();
      check(
        () => fsrs.currentRetrievability(
          memoryState: const FsrsMemoryState(stability: 5, difficulty: 5),
          daysElapsed: double.nan,
        ),
      ).throws<ArgumentError>();

      check(() {
        fsrs.evaluate([
          const FsrsItem(
            reviews: [FsrsReview(rating: FsrsRating.good, deltaT: -1)],
          ),
        ]);
      }).throws<ArgumentError>();

      check(() {
        fsrs.evaluate([
          const FsrsItem(
            reviews: [FsrsReview(rating: FsrsRating.manual, deltaT: 0)],
          ),
        ]);
      }).throws<ArgumentError>();
    });

    test('throws StateError after close', () {
      final localFsrs = Fsrs();
      localFsrs.close();
      check(localFsrs.nextStates).throws<StateError>();
      check(() => localFsrs.decay).throws<StateError>();
    });

    test('computes parameters on train set', () {
      const item1 = FsrsItem(
        reviews: [
          FsrsReview(rating: FsrsRating.good, deltaT: 0),
          FsrsReview(rating: FsrsRating.good, deltaT: 2),
          FsrsReview(rating: FsrsRating.easy, deltaT: 5),
        ],
      );
      const item2 = FsrsItem(
        reviews: [
          FsrsReview(rating: FsrsRating.hard, deltaT: 0),
          FsrsReview(rating: FsrsRating.again, deltaT: 1),
          FsrsReview(rating: FsrsRating.good, deltaT: 3),
        ],
      );

      final optimizedParams = fsrs.computeParameters([item1, item2]);
      check(optimizedParams).length.equals(21);
      for (final p in optimizedParams) {
        check(p.isFinite).isTrue();
      }

      final paramsWithOptions = fsrs.computeParameters(
        [item1, item2],
        enableShortTerm: false,
        numRelearningSteps: 1,
      );
      check(paramsWithOptions).length.equals(21);
      for (final p in paramsWithOptions) {
        check(p.isFinite).isTrue();
      }

      check(() {
        fsrs.computeParameters([item1], numRelearningSteps: -2);
      }).throws<ArgumentError>();
    });

    test('evaluates model on train set', () {
      const item1 = FsrsItem(
        reviews: [
          FsrsReview(rating: FsrsRating.good, deltaT: 0),
          FsrsReview(rating: FsrsRating.good, deltaT: 2),
          FsrsReview(rating: FsrsRating.easy, deltaT: 5),
        ],
      );
      const item2 = FsrsItem(
        reviews: [
          FsrsReview(rating: FsrsRating.hard, deltaT: 0),
          FsrsReview(rating: FsrsRating.again, deltaT: 1),
          FsrsReview(rating: FsrsRating.good, deltaT: 3),
        ],
      );

      final evaluation = fsrs.evaluate([item1, item2]);
      check(evaluation.logLoss.isFinite).isTrue();
      check(evaluation.logLoss).isGreaterThan(0.0);
      check(evaluation.rmseBins.isFinite).isTrue();
      check(evaluation.rmseBins).isGreaterOrEqual(0.0);

      check(() {
        fsrs.evaluate([]);
      }).throws<ArgumentError>();

      // Empty reviews item must not cause UB/crash
      check(() {
        fsrs.evaluate([const FsrsItem(reviews: [])]);
      }).throws<FsrsException>();
    });
  });

  group('ts-fsrs Aligned API (repeat, next, rollback, forget)', () {
    late Fsrs fsrs;

    setUp(() {
      fsrs = Fsrs();
    });

    tearDown(() {
      fsrs.close();
    });

    test('createEmptyCard creates newCard state', () {
      final card = fsrs.createEmptyCard();
      check(card.isNew).isTrue();
      check(card.state).equals(FsrsCardState.newCard);
      check(card.reps).equals(0);
      check(card.lapses).equals(0);
      check(card.step).equals(0);
      check(card.memoryState).isNull();
    });

    test('repeat returns all 4 ratings without mutating original card', () {
      final card = fsrs.createEmptyCard();
      final preview = fsrs.repeat(card);

      check(preview).length.equals(4);
      check(preview.containsKey(FsrsRating.again)).isTrue();
      check(preview.containsKey(FsrsRating.hard)).isTrue();
      check(preview.containsKey(FsrsRating.good)).isTrue();
      check(preview.containsKey(FsrsRating.easy)).isTrue();

      // Card remains unmodified
      check(card.isNew).isTrue();
      check(card.reps).equals(0);
    });

    test('next advances through learning steps and graduates', () {
      final now = DateTime.utc(2026, 9, 17, 12);
      final card0 = fsrs.createEmptyCard(now: now);

      // Step 0 -> Good -> advances to step 1 (10 min)
      final res1 = fsrs.next(card0, FsrsRating.good, now: now);
      check(res1.card.state).equals(FsrsCardState.learning);
      check(res1.card.step).equals(1);
      check(res1.card.reps).equals(1);
      check(res1.card.lapses).equals(0);
      check(res1.interval).equals(const Duration(minutes: 10));
      check(res1.card.due).equals(now.add(const Duration(minutes: 10)));
      check(res1.card.memoryState).isNotNull();

      // Step 1 -> Good -> graduates to review state!
      final reviewTime2 = now.add(const Duration(minutes: 10));
      final res2 = fsrs.next(res1.card, FsrsRating.good, now: reviewTime2);
      check(res2.card.state).equals(FsrsCardState.review);
      check(res2.card.step).equals(0);
      check(res2.card.reps).equals(2);
      check(res2.interval.inDays).isGreaterOrEqual(1);
      check(res2.card.due).equals(reviewTime2.add(res2.interval));
    });

    test('getRetrievability returns 0 for new card and decays sub-day', () {
      final now = DateTime.utc(2026, 9, 17, 12);
      final card = fsrs.createEmptyCard(now: now);
      check(fsrs.getRetrievability(card, now: now)).equals(0);

      // Review card into review state
      final res = fsrs.next(card, FsrsRating.easy, now: now);
      final r0 = fsrs.getRetrievability(res.card, now: now);
      check(r0)
        ..isGreaterOrEqual(0.99)
        ..isLessOrEqual(1.0);

      final halfDayLater = now.add(const Duration(hours: 12));
      final rHalf = fsrs.getRetrievability(res.card, now: halfDayLater);
      check(rHalf).isLessThan(r0);

      final later = now.add(const Duration(days: 10));
      final r10 = fsrs.getRetrievability(res.card, now: later);
      check(r10).isLessThan(rHalf);
    });

    test('again on review card increases lapses and enters relearning', () {
      final now = DateTime.utc(2026, 9, 17, 12);
      const memory = FsrsMemoryState(stability: 15, difficulty: 4);
      final reviewCard = FsrsCard(
        state: FsrsCardState.review,
        memoryState: memory,
        due: now,
        reps: 5,
        lastReview: now.subtract(const Duration(days: 15)),
      );

      final res = fsrs.next(reviewCard, FsrsRating.again, now: now);
      check(res.card.state).equals(FsrsCardState.relearning);
      check(res.card.step).equals(0);
      check(res.card.reps).equals(6);
      check(res.card.lapses).equals(1);
      check(res.interval).equals(const Duration(minutes: 10));
    });

    test('enableShortTerm false still increments lapses on review again', () {
      final longTermFsrs = Fsrs(enableShortTerm: false);
      addTearDown(longTermFsrs.close);

      final now = DateTime.utc(2026, 9, 17, 12);
      const memory = FsrsMemoryState(stability: 15, difficulty: 4);
      final reviewCard = FsrsCard(
        state: FsrsCardState.review,
        memoryState: memory,
        due: now,
        reps: 5,
        lastReview: now.subtract(const Duration(days: 15)),
      );

      final res = longTermFsrs.next(reviewCard, FsrsRating.again, now: now);
      check(res.card.state).equals(FsrsCardState.review);
      check(res.card.lapses).equals(1);
      check(res.card.reps).equals(6);
    });

    test('rollback losslessly restores card across all state transitions', () {
      final now = DateTime.utc(2026, 9, 17, 12);
      final card0 = fsrs.createEmptyCard(now: now);

      // newCard -> learning (step 1)
      final res1 = fsrs.next(card0, FsrsRating.good, now: now);
      check(fsrs.rollback(res1.card, res1.log)).equals(card0);

      // learning (step 1) -> review (step 0)
      final t2 = now.add(const Duration(minutes: 10));
      final res2 = fsrs.next(res1.card, FsrsRating.good, now: t2);
      check(fsrs.rollback(res2.card, res2.log)).equals(res1.card);

      // review -> relearning (again increments lapses)
      final t3 = res2.card.due;
      final res3 = fsrs.next(res2.card, FsrsRating.again, now: t3);
      check(res3.card.lapses).equals(1);
      check(fsrs.rollback(res3.card, res3.log)).equals(res2.card);

      // forget(resetCount: false) -> rollback restores exact card
      final forgotten = fsrs.forget(res2.card, now: t3);
      check(fsrs.rollback(forgotten.card, forgotten.log)).equals(res2.card);
    });

    test('forget resets card including step and lastReview', () {
      final now = DateTime.utc(2026, 9, 17, 12);
      final card0 = fsrs.createEmptyCard(now: now);
      // Advance to learning step 1
      final learning = fsrs.next(card0, FsrsRating.good, now: now).card;
      check(learning.step).equals(1);

      final forgotten = fsrs.forget(learning, now: now, resetCount: true);
      check(forgotten.card.state).equals(FsrsCardState.newCard);
      check(forgotten.card.step).equals(0);
      check(forgotten.card.reps).equals(0);
      check(forgotten.card.lapses).equals(0);
      check(forgotten.card.memoryState).isNull();
      check(forgotten.card.lastReview).isNull();
      check(forgotten.log.rating).equals(FsrsRating.manual);
      check(forgotten.log.due).equals(learning.due);

      // Next good review starts from step 0 -> advances to step 1 (not review)
      final afterForget = fsrs.next(
        forgotten.card,
        FsrsRating.good,
        now: now.add(const Duration(days: 5)),
      );
      check(afterForget.card.state).equals(FsrsCardState.learning);
      check(afterForget.card.step).equals(1);
    });

    test('next rejects manual rating with ArgumentError', () {
      final now = DateTime.utc(2026, 9, 17, 12);
      final card = fsrs.createEmptyCard(now: now);
      check(() {
        fsrs.next(card, FsrsRating.manual, now: now);
      }).throws<ArgumentError>();
    });

    test(
      'enableFuzz randomizes intervals and handles maximumInterval == 1',
      () {
        final fuzzedFsrs = Fsrs(enableFuzz: true, random: Random(42));
        addTearDown(fuzzedFsrs.close);

        final now = DateTime.utc(2026, 9, 17, 12);
        final card = fuzzedFsrs.createEmptyCard(now: now);
        final res1 = fuzzedFsrs.next(card, FsrsRating.easy, now: now);
        check(res1.card.state).equals(FsrsCardState.review);
        check(res1.interval.inDays).isGreaterThan(0);

        // maximumInterval == 1 must not throw in _applyFuzz
        final maxOneFsrs = Fsrs(
          enableFuzz: true,
          maximumInterval: 1,
          random: Random(42),
        );
        addTearDown(maxOneFsrs.close);
        final resMaxOne = maxOneFsrs.next(card, FsrsRating.easy, now: now);
        check(resMaxOne.interval).equals(const Duration(days: 1));
      },
    );

    test(
      'reschedule replays historical reviews and manual sub-day entries',
      () {
        final now = DateTime.utc(2026, 9, 17, 12);
        final emptyCard = fsrs.createEmptyCard(now: now);

        final reviews = [
          FsrsHistoryEntry(
            review: now.subtract(const Duration(days: 10)),
            rating: FsrsRating.good,
          ),
          FsrsHistoryEntry(
            review: now.subtract(const Duration(days: 5)),
            rating: FsrsRating.good,
          ),
          FsrsHistoryEntry(
            review: now,
            rating: FsrsRating.good,
          ),
        ];

        final result1 = fsrs.reschedule(emptyCard, reviews);
        final result2 = fsrs.reschedule(emptyCard, reviews);
        check(result1.collections).length.equals(3);
        check(result1.card.reps).equals(3);
        check(result1.card.lastReview).equals(now);
        check(result1.card.state).equals(FsrsCardState.review);
        check(result1).equals(result2);
        check(result1.hashCode).equals(result2.hashCode);

        // Manual entry preserves sub-day interval
        final manualDue = now.add(const Duration(hours: 6));
        final manualResult = fsrs.reschedule(
          emptyCard,
          [
            FsrsHistoryEntry(
              review: now,
              rating: FsrsRating.manual,
              state: FsrsCardState.review,
              due: manualDue,
              stability: 5,
              difficulty: 4,
            ),
          ],
          skipManual: false,
        );
        check(manualResult.collections.single.interval)
            .equals(const Duration(hours: 6));
        check(manualResult.card.step).equals(0);
      },
    );
  });
}
