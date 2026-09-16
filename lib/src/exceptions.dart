/// Exception thrown when an FSRS operation fails.
final class const FsrsException(
  final String message,
) implements Exception {
  @override
  String toString() => 'FsrsException: $message';
}
