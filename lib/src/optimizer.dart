import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:fsrs_dart/fsrs_dart.g.dart';
import 'package:fsrs_dart/src/exceptions.dart';
import 'package:fsrs_dart/src/model.dart';
import 'package:fsrs_dart/src/native.dart';
import 'package:fsrs_dart/src/review_log.dart';
import 'package:fsrs_dart/src/training.dart';

abstract final class FsrsOptimizer {
  /// Logs without a rating are skipped. A review of a new card starts a new
  /// history; reviews before it are skipped.
  ///
  /// Throws [ArgumentError] if a log has no card id.
  static List<FsrsTrainingItem> itemsFromLogs(Iterable<FsrsReviewLog> logs) {
    final byCard = <int, List<(int, FsrsReviewLog)>>{};
    for (final (index, log) in logs.indexed) {
      if (log.rating == null) continue;
      final cardId = log.cardId;
      if (cardId == null) {
        throw ArgumentError.value(log, 'logs', 'every log needs a cardId');
      }
      (byCard[cardId] ??= []).add((index, log));
    }

    final items = <FsrsTrainingItem>[];
    var historyId = 0;
    for (final cardLogs in byCard.values) {
      cardLogs.sort((a, b) {
        final byTime = a.$2.reviewedAt.compareTo(b.$2.reviewedAt);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });

      List<FsrsReview>? history;
      void flush() {
        final reviews = history;
        if (reviews == null || reviews.length < 2) return;
        for (var end = 2; end <= reviews.length; end++) {
          items.add(
            FsrsTrainingItem(
              cardId: historyId,
              reviews: reviews.sublist(0, end),
            ),
          );
        }
        historyId++;
      }

      for (final (_, log) in cardLogs) {
        final rating = log.rating!;
        if (log.phaseBefore == null) {
          flush();
          history = [FsrsReview(rating, Duration.zero)];
        } else {
          history?.add(FsrsReview(rating, log.elapsed));
        }
      }
      flush();
    }
    return items;
  }

  /// Runs in a background isolate. With too little data, returns
  /// `FsrsModel.defaults(version)`.
  ///
  /// Throws [ArgumentError] if [items] is empty, only some items have a card
  /// id, or [numRelearningSteps] is negative. The future may fail with
  /// [FsrsNotEnoughDataException].
  static Future<FsrsModel> computeParameters(
    List<FsrsTrainingItem> items, {
    FsrsVersion version = .v7,
    bool enableShortTerm = true,
    int? numRelearningSteps,
  }) {
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'must not be empty');
    }
    if (numRelearningSteps != null && numRelearningSteps < 0) {
      throw ArgumentError.value(
        numRelearningSteps,
        'numRelearningSteps',
        'must not be negative',
      );
    }
    final withIds = items.where((item) => item.cardId != null).length;
    if (withIds != 0 && withIds != items.length) {
      throw ArgumentError.value(
        items,
        'items',
        'either every item or none must have a cardId',
      );
    }
    return Isolate.run(
      () => _compute(items, version, enableShortTerm, numRelearningSteps),
    );
  }

  static FsrsModel _compute(
    List<FsrsTrainingItem> items,
    FsrsVersion version,
    bool enableShortTerm,
    int? numRelearningSteps,
  ) {
    final parameters = using((arena) {
      final trainingSet = writeTrainingSet(arena, items);
      final out = arena<Float>(maxParametersLength);
      final written = arena<Size>();
      checkStatus(
        fsrs_compute_parameters(
          trainingSet,
          version.value,
          enableShortTerm,
          numRelearningSteps ?? -1,
          out,
          maxParametersLength,
          written,
        ),
        'computeParameters',
      );
      return [for (var i = 0; i < written.value; i++) out[i]];
    });
    return FsrsModel(parameters: parameters);
  }
}
