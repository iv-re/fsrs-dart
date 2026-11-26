import 'package:fsrs_dart/src/card.dart';
import 'package:fsrs_dart/src/memory_state.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:meta/meta.dart';

@immutable
sealed class FsrsHistoryEntry {
  const FsrsHistoryEntry();

  factory FsrsHistoryEntry.review(DateTime at, FsrsRating rating) =
      FsrsHistoryReview;

  /// [phase] and [memory] override the card's phase and memory state. A new
  /// card becomes active only when both are given.
  factory FsrsHistoryEntry.manual(
    DateTime at, {
    required DateTime due,
    FsrsPhase? phase,
    FsrsMemoryState? memory,
  }) = FsrsHistoryManual;

  /// UTC.
  DateTime get at;
}

final class FsrsHistoryReview extends FsrsHistoryEntry {
  FsrsHistoryReview(DateTime at, this.rating) : at = at.toUtc();

  @override
  final DateTime at;

  final FsrsRating rating;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsHistoryReview && at == other.at && rating == other.rating;

  @override
  int get hashCode => Object.hash(at, rating);

  @override
  String toString() => 'FsrsHistoryReview($at, ${rating.name})';
}

final class FsrsHistoryManual extends FsrsHistoryEntry {
  /// Throws [ArgumentError] if [due] is before [at].
  FsrsHistoryManual(
    DateTime at, {
    required DateTime due,
    this.phase,
    this.memory,
  }) : at = at.toUtc(),
       due = due.toUtc() {
    if (this.due.isBefore(this.at)) {
      throw ArgumentError.value(due, 'due', 'must not be before at');
    }
  }

  @override
  final DateTime at;

  /// UTC.
  final DateTime due;

  /// `null` keeps the current phase.
  final FsrsPhase? phase;

  /// `null` keeps the current memory state.
  final FsrsMemoryState? memory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsHistoryManual &&
          at == other.at &&
          due == other.due &&
          phase == other.phase &&
          memory == other.memory;

  @override
  int get hashCode => Object.hash(at, due, phase, memory);

  @override
  String toString() =>
      'FsrsHistoryManual($at, due: $due, phase: ${phase?.name}, '
      'memory: $memory)';
}
