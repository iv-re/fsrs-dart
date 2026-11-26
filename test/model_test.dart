import 'dart:isolate';

import 'package:checks/checks.dart';
import 'package:fsrs_dart/fsrs_dart.dart';
import 'package:test/scaffolding.dart';

const _day = Duration(days: 1);

FsrsMemoryState _memory(double s, double d, [double? fast]) =>
    FsrsMemoryState(stability: s, difficulty: d, stabilityFast: fast);

void main() {
  group('construction', () {
    test('defaults to FSRS-7', () {
      final model = FsrsModel();
      check(model.version).equals(FsrsVersion.v7);
      check(model.parameters).length.equals(34);
      check(model).equals(FsrsModel.defaults(FsrsVersion.v7));
    });

    test('selects the version by parameter count', () {
      check(FsrsVersion.v6.parameterCount).equals(21);
      check(FsrsVersion.v7.parameterCount).equals(34);

      final v6 = FsrsModel(parameters: FsrsVersion.v6.defaultParameters);
      check(v6.version).equals(FsrsVersion.v6);
      check(v6.parameters).deepEquals(FsrsVersion.v6.defaultParameters);

      final v5 = FsrsModel(
        parameters: FsrsVersion.v6.defaultParameters.sublist(0, 19),
      );
      check(v5.version).equals(FsrsVersion.v6);
      check(v5.parameters).length.equals(21);
    });

    test('rejects malformed parameters', () {
      check(
        () => FsrsModel(parameters: const [1, 2, 3]),
      ).throws<FsrsInvalidParametersException>();
      final nan = [...FsrsVersion.v7.defaultParameters]..[5] = double.nan;
      check(
        () => FsrsModel(parameters: nan),
      ).throws<FsrsInvalidParametersException>();
    });

    test('is a value', () {
      final model = FsrsModel();
      final copy = FsrsModel(parameters: model.parameters);
      check(copy).equals(model);
      check(copy.hashCode).equals(model.hashCode);
      check(model).not((it) => it.equals(FsrsModel.defaults(FsrsVersion.v6)));
      check(() => model.parameters[0] = 1).throws<UnsupportedError>();
    });
  });

  group('memory state', () {
    test('stabilityFast defaults to stability', () {
      check(_memory(3, 5).stabilityFast).equals(3);
      check(_memory(3, 5, 2).stabilityFast).equals(2);
    });

    test('rejects invalid values', () {
      check(() => _memory(0, 5)).throws<ArgumentError>();
      check(() => _memory(double.nan, 5)).throws<ArgumentError>();
      check(() => _memory(3, double.infinity)).throws<ArgumentError>();
      check(() => _memory(3, 5, -1)).throws<ArgumentError>();
    });
  });

  for (final version in FsrsVersion.values) {
    group('inference (${version.name})', () {
      final model = FsrsModel.defaults(version);

      test('longer intervals for better ratings', () {
        final states = model.nextStates(
          null,
          elapsed: Duration.zero,
          desiredRetention: 0.9,
        );
        check(states.again.interval).isLessThan(states.hard.interval);
        check(states.hard.interval).isLessThan(states.good.interval);
        check(states.good.interval).isLessThan(states.easy.interval);
        check(states[FsrsRating.good]).equals(states.good);
      });

      test('retrievability reaches desired retention at the interval', () {
        final memory = model
            .nextStates(null, elapsed: Duration.zero, desiredRetention: 0.9)
            .good
            .memory;
        final interval = model.interval(memory, 0.85);
        check(model.retrievability(memory, interval)).isCloseTo(0.85, 1e-3);
        check(
          model.retrievability(memory, Duration.zero),
        ).isCloseTo(1, 1e-4);
        check(
          model.retrievability(memory, const Duration(hours: 30)),
        ).isLessThan(model.retrievability(memory, const Duration(hours: 26)));
      });

      test('memoryStateFromHistory matches replayed nextStates', () {
        final first = model
            .nextStates(null, elapsed: Duration.zero, desiredRetention: 0.9)
            .good
            .memory;
        final second = model
            .nextStates(first, elapsed: _day * 3, desiredRetention: 0.9)
            .hard
            .memory;
        final replayed = model.memoryStateFromHistory([
          FsrsReview(.good, Duration.zero),
          FsrsReview(.hard, _day * 3),
        ]);
        check(replayed.stability).isCloseTo(second.stability, 1e-3);
        check(replayed.difficulty).isCloseTo(second.difficulty, 1e-3);
        check(replayed.stabilityFast).isCloseTo(second.stabilityFast, 1e-3);
      });

      test('imports SM-2 cards', () {
        final memory = model.memoryStateFromSm2(
          easeFactor: 2.5,
          interval: _day * 30,
          sm2Retention: 0.9,
        );
        check(memory.stability).isGreaterThan(1);
      });

      test('validates arguments', () {
        final memory = _memory(3, 5);
        check(
          () => model.nextStates(
            memory,
            elapsed: const Duration(seconds: -1),
            desiredRetention: 0.9,
          ),
        ).throws<ArgumentError>();
        for (final retention in [0.0, 1.0, double.nan]) {
          check(
            () => model.nextStates(
              memory,
              elapsed: _day,
              desiredRetention: retention,
            ),
          ).throws<ArgumentError>();
        }
        check(() => model.interval(memory, 1.5)).throws<ArgumentError>();
        check(() => model.memoryStateFromHistory([])).throws<ArgumentError>();
        check(
          () => model.memoryStateFromSm2(
            easeFactor: 2.5,
            interval: Duration.zero,
            sm2Retention: 0.9,
          ),
        ).throws<ArgumentError>();
      });
    });
  }

  group('version differences', () {
    test('FSRS-7 distinguishes same-day from hours-later reviews', () {
      final model = FsrsModel();
      final first = model
          .nextStates(null, elapsed: Duration.zero, desiredRetention: 0.9)
          .good
          .memory;
      final sameDay = model.nextStates(
        first,
        elapsed: const Duration(minutes: 10),
        desiredRetention: 0.9,
      );
      final later = model.nextStates(
        first,
        elapsed: const Duration(hours: 6),
        desiredRetention: 0.9,
      );
      check(later.good.memory).not((it) => it.equals(sameDay.good.memory));
    });

    test('FSRS-6 ignores stabilityFast', () {
      final model = FsrsModel.defaults(FsrsVersion.v6);
      final a = model.nextStates(
        _memory(5, 5),
        elapsed: _day * 3,
        desiredRetention: 0.9,
      );
      final b = model.nextStates(
        _memory(5, 5, 1),
        elapsed: _day * 3,
        desiredRetention: 0.9,
      );
      check(a).equals(b);
      check(a.good.memory.stabilityFast).equals(a.good.memory.stability);
    });
  });

  group('isolates', () {
    test('a model works after being sent to another isolate', () async {
      final model = FsrsModel();
      final here = model.nextStates(
        _memory(4, 6, 3),
        elapsed: const Duration(hours: 40),
        desiredRetention: 0.9,
      );
      final there = await Isolate.run(
        () => model.nextStates(
          _memory(4, 6, 3),
          elapsed: const Duration(hours: 40),
          desiredRetention: 0.9,
        ),
      );
      check(there).equals(here);
    });
  });

  group('evaluate', () {
    List<FsrsTrainingItem> items({bool withIds = true}) {
      final cards = [
        [(3, 0.0), (3, 2.0), (3, 6.0), (4, 15.0)],
        [(2, 0.0), (1, 1.0), (3, 0.5), (3, 3.0)],
        [(3, 0.0), (1, 4.0), (3, 1.0), (3, 5.0)],
      ];
      return [
        for (final (id, card) in cards.indexed)
          for (var end = 2; end <= card.length; end++)
            FsrsTrainingItem(
              cardId: withIds ? id : null,
              reviews: [
                for (final (rating, days) in card.take(end))
                  FsrsReview(
                    FsrsRating.fromValue(rating),
                    Duration(minutes: (days * 24 * 60).round()),
                  ),
              ],
            ),
      ];
    }

    test('scores a training set with and without card ids', () async {
      final model = FsrsModel();
      for (final withIds in [true, false]) {
        final evaluation = await model.evaluate(items(withIds: withIds));
        check(evaluation.logLoss)
          ..isGreaterThan(0)
          ..has((it) => it.isFinite, 'isFinite').isTrue();
        check(evaluation.rmseBins.isFinite).isTrue();
      }
    });

    test('rejects empty sets and partial card ids', () {
      final model = FsrsModel();
      check(() => model.evaluate([])).throws<ArgumentError>();
      final mixed = [...items(), ...items(withIds: false)];
      check(model.evaluate(mixed)).throws<ArgumentError>();
    });

    test('training items must start with zero elapsed time', () {
      check(
        () => FsrsTrainingItem(reviews: [FsrsReview(.good, _day)]),
      ).throws<ArgumentError>();
      check(() => FsrsTrainingItem(reviews: const [])).throws<ArgumentError>();
    });
  });
}
