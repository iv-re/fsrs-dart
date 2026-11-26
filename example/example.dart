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

  if (result.card case FsrsActiveCard(:final memory)) {
    print('Stability: ${memory.stability}');
    print('Difficulty: ${memory.difficulty}');
  }

  final recall = scheduler.retrievability(
    result.card,
    now: now.add(const Duration(days: 1)),
  );
  print('Retrievability: ${(recall! * 100).toStringAsFixed(1)}%');
}
