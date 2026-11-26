import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:fsrs_dart/fsrs_dart.g.dart';
import 'package:fsrs_dart/src/exceptions.dart';
import 'package:fsrs_dart/src/memory_state.dart';
import 'package:fsrs_dart/src/native.dart';
import 'package:fsrs_dart/src/next_states.dart';
import 'package:fsrs_dart/src/training.dart';
import 'package:meta/meta.dart';

enum const FsrsVersion(final int value) {
  /// 21 parameters (17 and 19 are filled up).
  v6(6),

  /// 34 parameters.
  v7(7);

  int get parameterCount => fsrs_parameters_len(value);

  List<double> get defaultParameters => readFloatsInto(
    (out, length, written) =>
        fsrs_default_parameters(value, out, length, written),
    'FsrsVersion.defaultParameters',
  );

  static FsrsVersion _fromValue(int value) => switch (value) {
    6 => v6,
    7 => v7,
    _ => throw FsrsNativeException('Unknown model version: $value'),
  };
}

/// FSRS parameters and the memory model they define.
///
/// Can be sent to other isolates. Native resources are released
/// automatically.
@immutable
final class FsrsModel {
  /// `null` or an empty list selects the FSRS-7 defaults; 17, 19 or 21
  /// parameters select FSRS-6; 34 select FSRS-7. Throws
  /// [FsrsInvalidParametersException] for any other count or non-finite
  /// values.
  factory FsrsModel({List<double>? parameters}) {
    final native = NativeModel.create(parameters ?? const []);
    final model = FsrsModel._(
      FsrsVersion._fromValue(native.version),
      native.parameters,
    );
    _natives[model] = native;
    return model;
  }

  factory FsrsModel.defaults(FsrsVersion version) =>
      FsrsModel(parameters: version.defaultParameters);

  const FsrsModel._(this.version, this.parameters);

  static final Expando<NativeModel> _natives = Expando('FsrsModel');

  final FsrsVersion version;

  /// Filled to the full length of [version]. Unmodifiable.
  final List<double> parameters;

  NativeModel get _native => _natives[this] ??= NativeModel.create(parameters);

  /// [memory] is `null` for a new card. [elapsed] is the time since the last
  /// review.
  FsrsNextStates nextStates(
    FsrsMemoryState? memory, {
    required Duration elapsed,
    required double desiredRetention,
  }) {
    _checkElapsed(elapsed);
    _checkRetention(desiredRetention, 'desiredRetention');
    final native = _native;
    return using((arena) {
      final out = arena<fsrs_NextStates>();
      checkStatus(
        fsrs_next_states(
          native.pointer,
          writeOptionalMemory(arena, memory),
          desiredRetention,
          toDays(elapsed),
          out,
        ),
        'nextStates',
      );
      final states = out.ref;
      return FsrsNextStates(
        again: readItemState(states.again),
        hard: readItemState(states.hard),
        good: readItemState(states.good),
        easy: readItemState(states.easy),
      );
    });
  }

  /// The probability of recalling an item with [memory] after [elapsed].
  double retrievability(FsrsMemoryState memory, Duration elapsed) {
    _checkElapsed(elapsed);
    final native = _native;
    return using((arena) {
      final out = arena<Float>();
      checkStatus(
        fsrs_retrievability(
          native.pointer,
          writeMemory(arena, memory),
          toDays(elapsed),
          out,
        ),
        'retrievability',
      );
      return out.value;
    });
  }

  /// The time after which the probability of recall drops to
  /// [desiredRetention].
  Duration interval(FsrsMemoryState memory, double desiredRetention) {
    _checkRetention(desiredRetention, 'desiredRetention');
    final native = _native;
    return using((arena) {
      final out = arena<Float>();
      checkStatus(
        fsrs_next_interval(
          native.pointer,
          writeMemory(arena, memory),
          desiredRetention,
          out,
        ),
        'interval',
      );
      return fromDays(out.value);
    });
  }

  /// Replays [reviews] and returns the resulting memory state.
  ///
  /// Without [start], the first review introduces a new card and must have
  /// zero elapsed time. With [start] (e.g. from [memoryStateFromSm2]), the
  /// reviews continue a history whose beginning is not available.
  FsrsMemoryState memoryStateFromHistory(
    List<FsrsReview> reviews, {
    FsrsMemoryState? start,
  }) {
    if (reviews.isEmpty) {
      throw ArgumentError.value(reviews, 'reviews', 'must not be empty');
    }
    final native = _native;
    return using((arena) {
      final out = arena<fsrs_MemoryState>();
      checkStatus(
        fsrs_memory_state(
          native.pointer,
          writeReviews(arena, reviews),
          reviews.length,
          writeOptionalMemory(arena, start),
          out,
        ),
        'memoryStateFromHistory',
      );
      return readMemory(out.ref);
    });
  }

  /// Estimates the memory state of a card scheduled by SM-2.
  ///
  /// [interval] is the card's current interval and [sm2Retention] the
  /// retention SM-2 achieved on the collection. FSRS-7 ignores [easeFactor].
  FsrsMemoryState memoryStateFromSm2({
    required double easeFactor,
    required Duration interval,
    required double sm2Retention,
  }) {
    if (!easeFactor.isFinite || easeFactor <= 0) {
      throw ArgumentError.value(
        easeFactor,
        'easeFactor',
        'must be finite and positive',
      );
    }
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
    _checkRetention(sm2Retention, 'sm2Retention');
    final native = _native;
    return using((arena) {
      final out = arena<fsrs_MemoryState>();
      checkStatus(
        fsrs_memory_state_from_sm2(
          native.pointer,
          easeFactor,
          toDays(interval),
          sm2Retention,
          out,
        ),
        'memoryStateFromSm2',
      );
      return readMemory(out.ref);
    });
  }

  /// Runs in a background isolate. Throws [ArgumentError] if [items] is
  /// empty or only some items have a card id.
  Future<FsrsEvaluation> evaluate(List<FsrsTrainingItem> items) {
    if (items.isEmpty) {
      throw ArgumentError.value(items, 'items', 'must not be empty');
    }
    return Isolate.run(() => _evaluate(items));
  }

  FsrsEvaluation _evaluate(List<FsrsTrainingItem> items) {
    final native = _native;
    return using((arena) {
      final out = arena<fsrs_ModelEvaluation>();
      checkStatus(
        fsrs_evaluate(native.pointer, writeTrainingSet(arena, items), out),
        'evaluate',
      );
      return FsrsEvaluation(
        logLoss: out.ref.log_loss,
        rmseBins: out.ref.rmse_bins,
      );
    });
  }

  static void _checkElapsed(Duration elapsed) {
    if (elapsed.isNegative) {
      throw ArgumentError.value(elapsed, 'elapsed', 'must not be negative');
    }
  }

  static void _checkRetention(double value, String name) {
    if (!(value > 0 && value < 1)) {
      throw ArgumentError.value(value, name, 'must be between 0 and 1');
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! FsrsModel ||
        version != other.version ||
        parameters.length != other.parameters.length) {
      return false;
    }
    for (var i = 0; i < parameters.length; i++) {
      if (parameters[i] != other.parameters[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(version, Object.hashAll(parameters));

  @override
  String toString() => 'FsrsModel(${version.name}, $parameters)';
}
