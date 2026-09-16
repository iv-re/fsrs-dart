import 'package:fsrs_dart/fsrs_dart.dart';

void main() {
  final fsrs = Fsrs();
  final now = DateTime.now().toUtc();

  // Create a fresh card
  final card = fsrs.createEmptyCard(now: now);
  print('New card state: ${card.state.name}');

  // Preview next due intervals for all available grades
  final preview = fsrs.repeat(card, now: now);
  for (final entry in preview.entries) {
    print('${entry.key.name}: due in ${entry.value.interval}');
  }

  // User rates the card as "good"
  final result = fsrs.next(card, FsrsRating.good, now: now);
  print('Reviewed card due: ${result.card.due}');
  print('Stability: ${result.card.stability}');
  print('Difficulty: ${result.card.difficulty}');

  // Check recall probability at current time
  final retrievability = fsrs.getRetrievability(result.card, now: now);
  print('Retrievability: ${(retrievability * 100).toStringAsFixed(1)}%');
}
