/// Internal glue between the Dart API and the generated FFI bindings.
library;

import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:fsrs_dart/fsrs_dart.g.dart';
import 'package:fsrs_dart/src/exceptions.dart';
import 'package:fsrs_dart/src/item_state.dart';
import 'package:fsrs_dart/src/memory_state.dart';
import 'package:fsrs_dart/src/training.dart';

final int maxParametersLength = fsrs_parameters_len(7);

double toDays(Duration duration) =>
    duration.inMicroseconds / Duration.microsecondsPerDay;

Duration fromDays(double days) {
  if (!days.isFinite || days < 0) {
    throw FsrsNativeException('The engine returned an invalid interval: $days');
  }
  return Duration(microseconds: (days * Duration.microsecondsPerDay).round());
}

void checkStatus(fsrs_Status status, String operation) {
  switch (status) {
    case .fsrs_Status_Ok:
      return;
    case .fsrs_Status_InvalidParameters:
      throw FsrsInvalidParametersException(
        '$operation: the model parameters are invalid.',
      );
    case .fsrs_Status_NotEnoughData:
      throw FsrsNotEnoughDataException(
        '$operation: the training set has too few usable reviews.',
      );
    case .fsrs_Status_InvalidInput:
      throw ArgumentError('$operation: the engine rejected the input.');
    case .fsrs_Status_NullPointer ||
        .fsrs_Status_BufferTooSmall ||
        .fsrs_Status_Failed:
      throw FsrsNativeException('$operation failed (${status.name}).');
  }
}

/// Keep a local variable of this type alive for as long as [pointer] is in
/// use: as a [Finalizable] it is not collected before the end of its scope.
final class NativeModel implements Finalizable {
  NativeModel._(this.pointer) {
    _finalizer.attach(this, pointer.cast());
  }

  factory NativeModel.create(List<double> parameters) {
    final pointer = using((arena) {
      final input = writeFloats(arena, parameters);
      final out = arena<Pointer<fsrs_FSRS>>();
      checkStatus(fsrs_new(input, parameters.length, out), 'FsrsModel');
      return out.value;
    });
    return NativeModel._(pointer);
  }

  static final NativeFinalizer _finalizer = NativeFinalizer(
    Native.addressOf<NativeFunction<Void Function(Pointer<fsrs_FSRS>)>>(
      fsrs_free,
    ).cast(),
  );

  final Pointer<fsrs_FSRS> pointer;

  int get version => fsrs_version(pointer);

  List<double> get parameters => readFloatsInto(
    (out, length, written) => fsrs_parameters(pointer, out, length, written),
    'FsrsModel.parameters',
  );
}

Pointer<Float> writeFloats(Arena arena, List<double> values) {
  if (values.isEmpty) return nullptr;
  final pointer = arena<Float>(values.length);
  for (var i = 0; i < values.length; i++) {
    pointer[i] = values[i];
  }
  return pointer;
}

List<double> readFloatsInto(
  fsrs_Status Function(Pointer<Float> out, int length, Pointer<Size> written)
  call,
  String operation,
) {
  return using((arena) {
    final out = arena<Float>(maxParametersLength);
    final written = arena<Size>();
    checkStatus(call(out, maxParametersLength, written), operation);
    return List.unmodifiable([
      for (var i = 0; i < written.value; i++) out[i],
    ]);
  });
}

Pointer<fsrs_MemoryState> writeMemory(Arena arena, FsrsMemoryState memory) {
  return arena<fsrs_MemoryState>()
    ..ref.stability = memory.stability
    ..ref.difficulty = memory.difficulty
    ..ref.stability_fast = memory.stabilityFast;
}

Pointer<fsrs_MemoryState> writeOptionalMemory(
  Arena arena,
  FsrsMemoryState? memory,
) => memory == null ? nullptr : writeMemory(arena, memory);

FsrsMemoryState readMemory(fsrs_MemoryState state) {
  final stability = state.stability;
  final difficulty = state.difficulty;
  final stabilityFast = state.stability_fast;
  final valid =
      stability.isFinite &&
      stability > 0 &&
      difficulty.isFinite &&
      stabilityFast.isFinite &&
      stabilityFast > 0;
  if (!valid) {
    throw FsrsNativeException(
      'The engine returned an invalid state: stability $stability, '
      'difficulty $difficulty, stabilityFast $stabilityFast',
    );
  }
  return FsrsMemoryState(
    stability: stability,
    difficulty: difficulty,
    stabilityFast: stabilityFast,
  );
}

FsrsItemState readItemState(fsrs_ItemState state) => FsrsItemState(
  memory: readMemory(state.memory),
  interval: fromDays(state.interval),
);

Pointer<fsrs_Review> writeReviews(Arena arena, List<FsrsReview> reviews) {
  final pointer = arena<fsrs_Review>(reviews.length);
  for (var i = 0; i < reviews.length; i++) {
    pointer[i]
      ..rating = reviews[i].rating.value
      ..delta_t = toDays(reviews[i].elapsed);
  }
  return pointer;
}

/// Card ids are passed only when every item has one. Throws [ArgumentError]
/// if [items] is empty or only some items have a card id.
Pointer<fsrs_TrainingSet> writeTrainingSet(
  Arena arena,
  List<FsrsTrainingItem> items,
) {
  if (items.isEmpty) {
    throw ArgumentError.value(items, 'items', 'must not be empty');
  }
  final withIds = items.where((item) => item.cardId != null).length;
  if (withIds != 0 && withIds != items.length) {
    throw ArgumentError.value(
      items,
      'items',
      'either every item or none must have a cardId',
    );
  }

  final rawItems = arena<fsrs_TrainingItem>(items.length);
  final cardIds = withIds == 0 ? nullptr : arena<Int64>(items.length);
  for (var i = 0; i < items.length; i++) {
    final item = items[i];
    rawItems[i]
      ..reviews = writeReviews(arena, item.reviews)
      ..len = item.reviews.length;
    if (cardIds != nullptr) cardIds[i] = item.cardId!;
  }
  return arena<fsrs_TrainingSet>()
    ..ref.items = rawItems
    ..ref.len = items.length
    ..ref.card_ids = cardIds;
}
