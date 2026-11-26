import 'dart:math';

import 'package:checks/checks.dart';
import 'package:fsrs_dart/fsrs_dart.dart';
import 'package:test/scaffolding.dart';

final _start = DateTime.utc(2026);
const _day = Duration(days: 1);

List<FsrsReviewLog> _simulate({int cards = 60, int reviews = 8}) {
  final scheduler = FsrsScheduler();
  final random = Random(7);
  final logs = <FsrsReviewLog>[];
  for (var id = 0; id < cards; id++) {
    var card = FsrsCard.create(id: id, now: _start);
    for (var i = 0; i < reviews; i++) {
      final roll = random.nextDouble();
      final rating = roll < 0.15
          ? FsrsRating.again
          : roll < 0.25
          ? FsrsRating.hard
          : roll < 0.9
          ? FsrsRating.good
          : FsrsRating.easy;
      final late = Duration(hours: random.nextInt(48));
      final result = scheduler.review(card, rating, now: card.due.add(late));
      card = result.card;
      logs.add(result.log);
    }
  }
  return logs;
}

void main() {
  final scheduler = FsrsScheduler();

  group('itemsFromLogs', () {
    test('turns each history into its prefixes', () {
      var card = FsrsCard.create(id: 9, now: _start);
      final logs = <FsrsReviewLog>[];
      for (final (offset, rating) in [
        (Duration.zero, FsrsRating.good),
        (_day * 2, FsrsRating.again),
        (_day * 3, FsrsRating.good),
      ]) {
        final result = scheduler.review(card, rating, now: _start.add(offset));
        card = result.card;
        logs.add(result.log);
      }

      final items = FsrsOptimizer.itemsFromLogs(logs.reversed);
      check(items).length.equals(2);
      check(items.map((item) => item.reviews.length)).deepEquals([2, 3]);
      check(items.map((item) => item.cardId).toSet()).length.equals(1);
      check(items.last.reviews).deepEquals([
        FsrsReview(.good, Duration.zero),
        FsrsReview(.again, _day * 2),
        FsrsReview(.good, _day),
      ]);
    });

    test('splits histories at forget and skips manual entries', () {
      var card = FsrsCard.create(id: 1, now: _start);
      final logs = <FsrsReviewLog>[];
      void review(Duration offset, FsrsRating rating) {
        final result = scheduler.review(card, rating, now: _start.add(offset));
        card = result.card;
        logs.add(result.log);
      }

      review(Duration.zero, .good);
      review(_day, .good);
      final forgotten = scheduler.forget(card, now: _start.add(_day * 2));
      card = forgotten.card;
      logs.add(forgotten.log);
      review(_day * 3, .good);
      review(_day * 5, .easy);

      final items = FsrsOptimizer.itemsFromLogs(logs);
      check(items).length.equals(2);
      check(items[0].cardId).not((it) => it.equals(items[1].cardId));
      for (final item in items) {
        check(item.reviews.first.elapsed).equals(Duration.zero);
      }
    });

    test('skips reviews whose history start is unknown', () {
      final imported = FsrsActiveCard(
        id: 3,
        phase: .review,
        memory: FsrsMemoryState(stability: 10, difficulty: 5),
        due: _start,
        lastReview: _start.subtract(_day * 10),
      );
      final first = scheduler.review(imported, .good, now: _start);
      final second = scheduler.review(
        first.card,
        .good,
        now: first.card.due,
      );
      check(FsrsOptimizer.itemsFromLogs([first.log, second.log])).isEmpty();
    });

    test('requires card ids', () {
      final log = scheduler.review(FsrsCard.create(now: _start), .good).log;
      check(
        () => FsrsOptimizer.itemsFromLogs([log]),
      ).throws<ArgumentError>();
    });
  });

  group('computeParameters', () {
    final items = FsrsOptimizer.itemsFromLogs(_simulate());

    for (final version in FsrsVersion.values) {
      test('fits a ${version.name} model', () async {
        final model = await FsrsOptimizer.computeParameters(
          items,
          version: version,
          numRelearningSteps: 1,
        );
        check(model.version).equals(version);
        check(model.parameters.every((value) => value.isFinite)).isTrue();
        check(model).not((it) => it.equals(FsrsModel.defaults(version)));

        final evaluation = await model.evaluate(items);
        check(evaluation.logLoss.isFinite).isTrue();

        final scheduled = FsrsScheduler(
          model: model,
        ).review(FsrsCard.create(now: _start), .easy, now: _start);
        check(scheduled.log.interval).isGreaterOrEqual(_day);
      });
    }

    test('works without card ids', () async {
      final anonymous = [
        for (final item in items) FsrsTrainingItem(reviews: item.reviews),
      ];
      final model = await FsrsOptimizer.computeParameters(anonymous);
      check(model.version).equals(FsrsVersion.v7);
    });

    test('returns the defaults when there is too little data', () async {
      final tiny = [
        FsrsTrainingItem(
          reviews: [
            FsrsReview(.good, Duration.zero),
            FsrsReview(.good, _day * 3),
          ],
        ),
      ];
      for (final version in FsrsVersion.values) {
        final model = await FsrsOptimizer.computeParameters(
          tiny,
          version: version,
        );
        check(model).equals(FsrsModel.defaults(version));
      }
    });

    test('validates arguments', () {
      check(
        () => FsrsOptimizer.computeParameters(const []),
      ).throws<ArgumentError>();
      check(
        () => FsrsOptimizer.computeParameters(items, numRelearningSteps: -1),
      ).throws<ArgumentError>();
      final mixed = [
        ...items.take(3),
        FsrsTrainingItem(reviews: items.first.reviews),
      ];
      check(
        () => FsrsOptimizer.computeParameters(mixed),
      ).throws<ArgumentError>();
    });
  });
}
