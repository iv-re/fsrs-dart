import 'package:meta/meta.dart';

/// Exception thrown when an FSRS operation fails.
@immutable
final class const FsrsException(
  final String message,
) implements Exception {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsException &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'FsrsException: $message';
}
