import 'dart:ffi';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:fsrs_dart/fsrs_dart.g.dart';
import 'package:fsrs_dart/src/card.dart';
import 'package:fsrs_dart/src/exceptions.dart';
import 'package:fsrs_dart/src/history.dart';
import 'package:fsrs_dart/src/item_state.dart';
import 'package:fsrs_dart/src/memory_state.dart';
import 'package:fsrs_dart/src/model_evaluation.dart';
import 'package:fsrs_dart/src/next_states.dart';
import 'package:fsrs_dart/src/rating.dart';
import 'package:fsrs_dart/src/review_log.dart';
import 'package:fsrs_dart/src/scheduler.dart';
import 'package:fsrs_dart/src/scheduling_result.dart';
import 'package:fsrs_dart/src/training.dart';

/// The Free Spaced Repetition Scheduler (FSRS) engine.
///
/// Implements [Finalizable] so underlying Rust memory is safely released
/// by [NativeFinalizer] when the instance is garbage-collected, or
/// explicitly via [close].
final class Fsrs implements Finalizable {
  /// Creates an FSRS instance with optional custom [parameters] and scheduling
  /// policies matching `ts-fsrs`.
  factory Fsrs({
    List<double>? parameters,
    double desiredRetention = 0.9,
    List<Duration> learningSteps = const [
      Duration(minutes: 1),
      Duration(minutes: 10),
    ],
    List<Duration> relearningSteps = const [
      Duration(minutes: 10),
    ],
    int maximumInterval = 36500,
    bool enableShortTerm = true,
    bool enableFuzz = false,
    Random? random,
  }) {
    final ptr = using((arena) {
      if (parameters == null || parameters.isEmpty) {
        return fsrs_new(nullptr, 0);
      }
      final paramsPtr = arena<Float>(parameters.length);
      for (var i = 0; i < parameters.length; i++) {
        paramsPtr[i] = parameters[i];
      }
      return fsrs_new(paramsPtr, parameters.length);
    });

    if (ptr == nullptr) {
      throw const FsrsException('Failed to initialize FSRS model');
    }

    final fsrs = Fsrs._(ptr);
    fsrs._scheduler = FsrsScheduler(
      fsrs: fsrs,
      desiredRetention: desiredRetention,
      learningSteps: learningSteps,
      relearningSteps: relearningSteps,
      maximumInterval: maximumInterval,
      enableShortTerm: enableShortTerm,
      enableFuzz: enableFuzz,
      random: random,
    );

    _finalizer.attach(fsrs, ptr.cast(), detach: fsrs);
    return fsrs;
  }

  Fsrs._(this._ptr);

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<fsrs_FSRS>)>>(
      fsrs_free,
    ).cast(),
  );

  final Pointer<fsrs_FSRS> _ptr;
  late final FsrsScheduler _scheduler;
  bool _isClosed = false;

  /// The internal scheduler managing learning and relearning steps.
  FsrsScheduler get scheduler => _scheduler;

  /// Whether this FSRS instance has been closed.
  bool get isClosed => _isClosed;

  void _checkClosed() {
    if (_isClosed) {
      throw StateError('Cannot use FSRS after it has been closed.');
    }
  }

  /// Returns the default 21 model parameters for FSRS-6.
  static List<double> get defaultParameters {
    return using((arena) {
      final len = fsrs_parameters_len();
      final ptr = arena<Float>(len);
      fsrs_default_parameters(ptr);
      return List<double>.generate(len, (i) => ptr[i]);
    });
  }

  /// Returns the default decay parameter (FSRS6_DEFAULT_DECAY).
  static double get defaultDecay => fsrs_default_decay();

  /// Creates a brand new empty card (matching `createEmptyCard` in `ts-fsrs`).
  FsrsCard createEmptyCard({DateTime? now, int? cardId}) {
    return _scheduler.createEmptyCard(now: now, cardId: cardId);
  }

  /// Previews the outcome of all 4 ratings without mutating [card]
  /// (matching `repeat(card, now)` in `ts-fsrs`).
  FsrsRecordLog repeat(FsrsCard card, {DateTime? now}) {
    _checkClosed();
    return _scheduler.preview(card, reviewDate: now);
  }

  /// Reviews [card] with [rating] and returns the updated card and review log
  /// (matching `next(card, now, rating)` in `ts-fsrs`).
  FsrsRecordLogItem next(
    FsrsCard card,
    FsrsRating rating, {
    DateTime? now,
  }) {
    _checkClosed();
    return _scheduler.reviewCard(card, rating, reviewDate: now);
  }

  /// Calculates the retrievability (probability of recall) for [card] at [now]
  /// (matching `get_retrievability` in `ts-fsrs`).
  double getRetrievability(
    FsrsCard card, {
    DateTime? now,
    double? decay,
  }) {
    _checkClosed();
    final mem = card.memoryState;
    if (mem == null) {
      return 0;
    }

    final reviewTime = (now ?? DateTime.now()).toUtc();
    final lastRev = card.lastReview;
    final daysElapsed = lastRev != null
        ? reviewTime.difference(lastRev).inDays.clamp(0, 100000).toDouble()
        : 0.0;

    return currentRetrievability(
      memoryState: mem,
      daysElapsed: daysElapsed,
      decay: decay,
    );
  }

  /// Reverts a review given the [card] and the corresponding [log]
  /// (matching `rollback` in `ts-fsrs`).
  FsrsCard rollback(FsrsCard card, FsrsReviewLog log) {
    return _scheduler.rollback(card, log);
  }

  /// Resets [card] back to unlearned status
  /// (matching `forget` in `ts-fsrs`).
  FsrsRecordLogItem forget(
    FsrsCard card, {
    DateTime? now,
    bool resetCount = false,
  }) {
    return _scheduler.forget(card, now: now, resetCount: resetCount);
  }

  /// Calculates the next memory states and intervals for all 4 ratings.
  ///
  /// [memoryState] is null for new cards that have never been reviewed.
  /// [desiredRetention] target retention rate (0.0 to 1.0, default 0.9).
  /// [daysElapsed] days elapsed since the last review (0 for new cards).
  FsrsNextStates nextStates({
    FsrsMemoryState? memoryState,
    double desiredRetention = 0.9,
    int daysElapsed = 0,
  }) {
    _checkClosed();

    final statesPtr = using((arena) {
      var memPtr = nullptr as Pointer<fsrs_MemoryState>;
      if (memoryState != null) {
        memPtr = arena<fsrs_MemoryState>()
          ..ref.stability = memoryState.stability
          ..ref.difficulty = memoryState.difficulty;
      }
      return fsrs_next_states(_ptr, memPtr, desiredRetention, daysElapsed);
    });

    if (statesPtr == nullptr) {
      throw FsrsException(
        'Failed to compute next states (retention: $desiredRetention, '
        'days: $daysElapsed).',
      );
    }

    try {
      return FsrsNextStates(
        again: _convertItemState(statesPtr.ref.again),
        hard: _convertItemState(statesPtr.ref.hard),
        good: _convertItemState(statesPtr.ref.good),
        easy: _convertItemState(statesPtr.ref.easy),
      );
    } finally {
      fsrs_next_states_free(statesPtr);
    }
  }

  /// Computes the next state directly for a specific [rating].
  FsrsItemState nextState({
    required FsrsRating rating,
    FsrsMemoryState? memoryState,
    double desiredRetention = 0.9,
    int daysElapsed = 0,
  }) {
    return nextStates(
      memoryState: memoryState,
      desiredRetention: desiredRetention,
      daysElapsed: daysElapsed,
    )[rating];
  }

  /// Computes the retrievability (probability of recall between 0.0 and 1.0).
  ///
  /// Uses [decay] if provided, otherwise defaults to [defaultDecay].
  double currentRetrievability({
    required FsrsMemoryState memoryState,
    required double daysElapsed,
    double? decay,
  }) {
    _checkClosed();
    final d = decay ?? defaultDecay;

    return using((arena) {
      final memPtr = arena<fsrs_MemoryState>()
        ..ref.stability = memoryState.stability
        ..ref.difficulty = memoryState.difficulty;
      return fsrs_current_retrievability(memPtr, daysElapsed, d);
    });
  }

  /// Optimizes model parameters based on the provided [trainSet].
  ///
  /// [enableShortTerm] whether to enable short-term memory parameters
  /// (default true).
  /// [numRelearningSteps] optional number of relearning steps.
  ///
  /// Returns a list of 21 optimized model parameters.
  List<double> computeParameters(
    List<FsrsItem> trainSet, {
    bool enableShortTerm = true,
    int? numRelearningSteps,
  }) {
    _checkClosed();
    if (trainSet.isEmpty) {
      throw ArgumentError.value(
        trainSet,
        'trainSet',
        'Train set cannot be empty.',
      );
    }
    if (numRelearningSteps != null && numRelearningSteps < 0) {
      throw ArgumentError.value(
        numRelearningSteps,
        'numRelearningSteps',
        'Number of relearning steps must be non-negative.',
      );
    }

    return using((arena) {
      final trainSetPtr = _marshalTrainSet(arena, trainSet);

      final resPtr = fsrs_compute_parameters(
        _ptr,
        trainSetPtr,
        enableShortTerm,
        numRelearningSteps ?? -1,
      );
      if (resPtr == nullptr) {
        throw const FsrsException(
          'Failed to compute parameters from training set.',
        );
      }

      try {
        final len = fsrs_parameters_len();
        return List<double>.generate(len, (i) => resPtr[i]);
      } finally {
        fsrs_parameters_free(resPtr);
      }
    });
  }

  /// Evaluates this FSRS model against the given [trainSet].
  ///
  /// Returns [FsrsModelEvaluation] containing log loss and RMSE bins metrics
  /// (matching `evaluate` in `ts-fsrs`).
  FsrsModelEvaluation evaluate(List<FsrsItem> trainSet) {
    _checkClosed();
    if (trainSet.isEmpty) {
      throw ArgumentError.value(
        trainSet,
        'trainSet',
        'Train set cannot be empty.',
      );
    }

    return using((arena) {
      final trainSetPtr = _marshalTrainSet(arena, trainSet);
      final evalPtr = arena<fsrs_ModelEvaluation>();

      final ok = fsrs_evaluate(_ptr, trainSetPtr, evalPtr);
      if (!ok) {
        throw const FsrsException(
          'Failed to evaluate model on training set.',
        );
      }

      return FsrsModelEvaluation(
        logLoss: evalPtr.ref.log_loss,
        rmseBins: evalPtr.ref.rmse_bins,
      );
    });
  }

  /// Reschedules [currentCard] by replaying a sequence of [reviews]
  /// (matching `reschedule` in `ts-fsrs`).
  FsrsRescheduleResult reschedule(
    FsrsCard currentCard,
    List<FsrsHistoryEntry> reviews, {
    bool skipManual = true,
  }) {
    _checkClosed();
    return _scheduler.reschedule(
      currentCard,
      reviews,
      skipManual: skipManual,
    );
  }

  static Pointer<fsrs_FsrsItems> _marshalTrainSet(
    Arena arena,
    List<FsrsItem> trainSet,
  ) {
    final itemsPtr = arena<fsrs_FSRSItem>(trainSet.length);

    for (var i = 0; i < trainSet.length; i++) {
      final item = trainSet[i];
      final reviewsPtr = arena<fsrs_FSRSReview>(item.reviews.length);

      for (var j = 0; j < item.reviews.length; j++) {
        final review = item.reviews[j];
        reviewsPtr[j]
          ..rating = review.rating.value
          ..delta_t = review.deltaT;
      }

      itemsPtr[i]
        ..reviews = reviewsPtr
        ..len = item.reviews.length;
    }

    return arena<fsrs_FsrsItems>()
      ..ref.items = itemsPtr
      ..ref.len = trainSet.length;
  }

  static FsrsItemState _convertItemState(fsrs_ItemState state) {
    return FsrsItemState(
      memory: FsrsMemoryState(
        stability: state.memory.stability,
        difficulty: state.memory.difficulty,
      ),
      interval: state.interval,
    );
  }

  /// Explicitly releases the underlying Rust resources.
  void close() {
    if (!_isClosed) {
      _isClosed = true;
      _finalizer.detach(this);
      fsrs_free(_ptr);
    }
  }
}
