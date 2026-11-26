/// Invalid arguments that can be checked up front (retention outside (0, 1),
/// negative elapsed time, ...) throw [ArgumentError] instead.
sealed class FsrsException implements Exception {
  const FsrsException(this.message);

  final String message;

  String get _name;

  @override
  String toString() => '$_name: $message';
}

/// The model parameters are malformed: wrong count, non-finite values, ...
final class FsrsInvalidParametersException extends FsrsException {
  const FsrsInvalidParametersException(super.message);

  @override
  String get _name => 'FsrsInvalidParametersException';
}

/// The training set has too few usable reviews.
final class FsrsNotEnoughDataException extends FsrsException {
  const FsrsNotEnoughDataException(super.message);

  @override
  String get _name => 'FsrsNotEnoughDataException';
}

/// An unexpected failure inside the native FSRS engine.
final class FsrsNativeException extends FsrsException {
  const FsrsNativeException(super.message);

  @override
  String get _name => 'FsrsNativeException';
}
