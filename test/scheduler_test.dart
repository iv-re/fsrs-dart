import 'package:checks/checks.dart';
import 'package:fsrs_dart/fsrs_dart.dart';
import 'package:test/scaffolding.dart';

final _now = DateTime.utc(2026, 9, 17, 12);
const _minute = Duration(minutes: 1);
const _day = Duration(days: 1);

FsrsActiveCard _reviewCard({int? id, int reps = 5, double stability = 15}) =>
    FsrsActiveCard(
      id: id,
      phase: .review,
      memory: FsrsMemoryState(stability: stability, difficulty: 4),
      due: _now,
      lastReview: _now.subtract(_day * 15),
      reps: reps,
    );

void main() {
  final scheduler = FsrsScheduler();

  group('cards', () {
    test('create makes a new card due now in UTC', () {
      final local = DateTime(2026, 9, 17, 12);
      final card = FsrsCard.create(id: 7, now: local);
      check(card).isA<FsrsNewCard>()
        ..has((it) => it.id, 'id').equals(7)
        ..has((it) => it.due, 'due').equals(local.toUtc())
        ..has((it) => it.reps, 'reps').equals(0);
    });

    test('reject impossible states', () {
      check(
        () => FsrsActiveCard(
          phase: .review,
          step: 1,
          memory: FsrsMemoryState(stability: 1, difficulty: 5),
          due: _now,
          lastReview: _now,
        ),
      ).throws<ArgumentError>();
      check(() => FsrsNewCard(due: _now, reps: -1)).throws<ArgumentError>();
    });
  });

  group('learning', () {
    test('good walks the learning steps and graduates', () {
      final first = scheduler.review(
        FsrsCard.create(now: _now),
        .good,
        now: _now,
      );
      check(first.card).isA<FsrsActiveCard>()
        ..has((it) => it.phase, 'phase').equals(FsrsPhase.learning)
        ..has((it) => it.step, 'step').equals(1)
        ..has((it) => it.reps, 'reps').equals(1)
        ..has((it) => it.due, 'due').equals(_now.add(_minute * 10));
      check(first.log)
        ..has((it) => it.rating, 'rating').equals(FsrsRating.good)
        ..has((it) => it.phaseBefore, 'phaseBefore').isNull()
        ..has((it) => it.interval, 'interval').equals(_minute * 10);

      final t2 = _now.add(_minute * 10);
      final second = scheduler.review(first.card, .good, now: t2);
      check(second.card).isA<FsrsActiveCard>()
        ..has((it) => it.phase, 'phase').equals(FsrsPhase.review)
        ..has((it) => it.step, 'step').equals(0);
      check(second.log.interval.inDays).isGreaterOrEqual(1);
      check(second.card.due).equals(t2.add(second.log.interval));
      check(second.log.elapsed).equals(_minute * 10);
    });

    test('hard on the first step waits between the first two steps', () {
      final result = scheduler.review(
        FsrsCard.create(now: _now),
        .hard,
        now: _now,
      );
      check(result.log.interval).equals(const Duration(seconds: 330));
      check((result.card as FsrsActiveCard).step).equals(0);
    });

    test('easy graduates immediately', () {
      final result = scheduler.review(
        FsrsCard.create(now: _now),
        .easy,
        now: _now,
      );
      check((result.card as FsrsActiveCard).phase).equals(FsrsPhase.review);
    });
  });

  group('review phase', () {
    test('again lapses into relearning', () {
      final result = scheduler.review(_reviewCard(), .again, now: _now);
      check(result.card).isA<FsrsActiveCard>()
        ..has((it) => it.phase, 'phase').equals(FsrsPhase.relearning)
        ..has((it) => it.step, 'step').equals(0)
        ..has((it) => it.reps, 'reps').equals(6)
        ..has((it) => it.lapses, 'lapses').equals(1);
      check(result.log.interval).equals(_minute * 10);
      check(result.log.elapsed).equals(_day * 15);
    });

    test('without short-term steps again stays in review but lapses', () {
      final longTerm = FsrsScheduler(enableShortTerm: false);
      final result = longTerm.review(_reviewCard(), .again, now: _now);
      check(result.card).isA<FsrsActiveCard>()
        ..has((it) => it.phase, 'phase').equals(FsrsPhase.review)
        ..has((it) => it.lapses, 'lapses').equals(1);
      check(result.log.interval).equals(_day);
    });

    test('intervals are whole days ordered hard <= good < easy', () {
      final fuzzy = FsrsScheduler(enableFuzz: true);
      for (var id = 0; id < 200; id++) {
        final preview = fuzzy.preview(_reviewCard(id: id), now: _now);
        final hard = preview.hard.log.interval;
        final good = preview.good.log.interval;
        final easy = preview.easy.log.interval;
        for (final interval in [hard, good, easy]) {
          check(interval.inMicroseconds % _day.inMicroseconds).equals(0);
        }
        check(hard).isLessOrEqual(good);
        check(good).isLessThan(easy);
      }
    });

    test('a lower desired retention gives longer intervals', () {
      final card = _reviewCard();
      final strict = scheduler.review(card, .good, now: _now);
      final relaxed = scheduler.review(
        card,
        .good,
        now: _now,
        desiredRetention: 0.8,
      );
      check(relaxed.log.interval).isGreaterThan(strict.log.interval);
    });

    test('respects maximumInterval', () {
      final capped = FsrsScheduler(maximumInterval: _day * 3);
      final preview = capped.preview(_reviewCard(stability: 400), now: _now);
      check(preview.easy.log.interval).isLessOrEqual(_day * 3);

      final one = FsrsScheduler(enableFuzz: true, maximumInterval: _day);
      check(
        one.review(_reviewCard(), .easy, now: _now).log.interval,
      ).equals(_day);
    });
  });

  group('fuzz', () {
    test('preview agrees with review for every rating', () {
      final fuzzy = FsrsScheduler(enableFuzz: true, fuzzSeed: 3);
      for (var id = 0; id < 50; id++) {
        final card = _reviewCard(id: id);
        final preview = fuzzy.preview(card, now: _now);
        for (final rating in FsrsRating.values) {
          check(fuzzy.review(card, rating, now: _now)).equals(preview[rating]);
        }
      }
    });

    test('spreads intervals across cards within a few days', () {
      final fuzzy = FsrsScheduler(enableFuzz: true);
      final plain = scheduler.review(_reviewCard(), .good, now: _now);
      final days = {
        for (var id = 0; id < 100; id++)
          fuzzy
              .review(_reviewCard(id: id), .good, now: _now)
              .log
              .interval
              .inDays,
      };
      check(days.length).isGreaterThan(1);
      final base = plain.log.interval.inDays;
      for (final day in days) {
        check((day - base).abs()).isLessOrEqual((base * 0.1).ceil() + 2);
      }
    });

    test('is deterministic for a seed and changes with it', () {
      List<int> run(int seed) {
        final fuzzy = FsrsScheduler(enableFuzz: true, fuzzSeed: seed);
        return [
          for (var id = 0; id < 30; id++)
            fuzzy
                .review(_reviewCard(id: id), .good, now: _now)
                .log
                .interval
                .inDays,
        ];
      }

      check(run(1)).deepEquals(run(1));
      check(run(1)).not((it) => it.deepEquals(run(2)));
    });
  });

  group('undo and forget', () {
    test('undo restores every transition exactly', () {
      final card0 = FsrsCard.create(id: 1, now: _now);
      final r1 = scheduler.review(card0, .good, now: _now);
      check(scheduler.undo(r1.card, r1.log)).equals(card0);

      final t2 = _now.add(_minute * 10);
      final r2 = scheduler.review(r1.card, .good, now: t2);
      check(scheduler.undo(r2.card, r2.log)).equals(r1.card);

      final r3 = scheduler.review(r2.card, .again, now: r2.card.due);
      check(r3.card.lapses).equals(1);
      check(scheduler.undo(r3.card, r3.log)).equals(r2.card);

      final forgotten = scheduler.forget(r3.card, now: t2, resetCounts: true);
      check(forgotten.card.reps).equals(0);
      check(scheduler.undo(forgotten.card, forgotten.log)).equals(r3.card);
    });

    test('undo rejects a log of another card', () {
      final a = scheduler.review(FsrsCard.create(id: 1, now: _now), .good);
      final b = FsrsCard.create(id: 2, now: _now);
      check(() => scheduler.undo(b, a.log)).throws<ArgumentError>();
    });

    test('forget resets to a new card', () {
      final learning = scheduler
          .review(FsrsCard.create(now: _now), .good, now: _now)
          .card;
      final kept = scheduler.forget(learning, now: _now);
      check(kept.card)
          .isA<FsrsNewCard>()
          .has((it) => it.reps, 'reps')
          .equals(1);
      check(kept.log)
        ..has((it) => it.rating, 'rating').isNull()
        ..has((it) => it.dueBefore, 'dueBefore').equals(learning.due);

      final reset = scheduler.forget(learning, now: _now, resetCounts: true);
      check(reset.card.reps).equals(0);

      final again = scheduler.review(reset.card, .good, now: _now.add(_day));
      check((again.card as FsrsActiveCard).phase).equals(FsrsPhase.learning);
    });
  });

  group('retrievability', () {
    test('is null for new cards and decays within a day', () {
      check(scheduler.retrievability(FsrsCard.create(now: _now))).isNull();
      final card = scheduler
          .review(FsrsCard.create(now: _now), .easy, now: _now)
          .card;
      final r0 = scheduler.retrievability(card, now: _now)!;
      final r12h = scheduler.retrievability(
        card,
        now: _now.add(const Duration(hours: 12)),
      )!;
      final r10d = scheduler.retrievability(card, now: _now.add(_day * 10))!;
      check(r0).isGreaterThan(0.99);
      check(r12h).isLessThan(r0);
      check(r10d).isLessThan(r12h);
    });
  });

  group('reschedule', () {
    test('replays reviews like reviewing one by one', () {
      final history = [
        FsrsHistoryEntry.review(_now, .good),
        FsrsHistoryEntry.review(_now.subtract(_day * 10), .good),
        FsrsHistoryEntry.review(_now.subtract(_day * 5), .hard),
      ];
      final result = scheduler.reschedule(
        FsrsCard.create(id: 4, now: _now),
        history,
      );
      check(result.logs).length.equals(3);
      check(result.card)
        ..has((it) => it.id, 'id').equals(4)
        ..has((it) => it.reps, 'reps').equals(3);
      check(
        result.logs.map((log) => log.reviewedAt),
      ).deepEquals([_now.subtract(_day * 10), _now.subtract(_day * 5), _now]);

      FsrsCard card = FsrsNewCard(id: 4, due: _now.subtract(_day * 10));
      for (final (at, rating) in [
        (_now.subtract(_day * 10), FsrsRating.good),
        (_now.subtract(_day * 5), FsrsRating.hard),
        (_now, FsrsRating.good),
      ]) {
        card = scheduler.review(card, rating, now: at).card;
      }
      check(result.card).equals(card);
      check(scheduler.reschedule(card, history)).equals(result);
    });

    test('applies manual entries', () {
      final memory = FsrsMemoryState(stability: 5, difficulty: 4);
      final result = scheduler.reschedule(FsrsCard.create(now: _now), [
        FsrsHistoryEntry.manual(
          _now,
          due: _now.add(const Duration(hours: 6)),
          phase: .review,
          memory: memory,
        ),
      ]);
      check(result.card).isA<FsrsActiveCard>()
        ..has((it) => it.memory, 'memory').equals(memory)
        ..has((it) => it.reps, 'reps').equals(0);
      check(result.logs.single)
        ..has((it) => it.rating, 'rating').isNull()
        ..has((it) => it.interval, 'interval').equals(
          const Duration(hours: 6),
        );

      check(
        () => scheduler.reschedule(FsrsCard.create(now: _now), [
          FsrsHistoryEntry.manual(_now, due: _now, phase: .review),
        ]),
      ).throws<ArgumentError>();
    });
  });

  group('configuration', () {
    test('validates options', () {
      check(() => FsrsScheduler(desiredRetention: 1)).throws<ArgumentError>();
      check(
        () => FsrsScheduler(learningSteps: const [Duration.zero]),
      ).throws<ArgumentError>();
      check(
        () => FsrsScheduler(maximumInterval: const Duration(hours: 12)),
      ).throws<ArgumentError>();
      check(
        () => scheduler.review(_reviewCard(), .good, desiredRetention: 0),
      ).throws<ArgumentError>();
    });

    test('works with an FSRS-6 model', () {
      final v6 = FsrsScheduler(model: FsrsModel.defaults(FsrsVersion.v6));
      final result = v6.review(_reviewCard(), .good, now: _now);
      check(result.log.interval.inDays).isGreaterThan(15);
    });
  });
}
