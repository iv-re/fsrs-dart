enum const FsrsRating(final int value) {
  /// The card was forgotten.
  again(1),

  /// Recalled with serious difficulty.
  hard(2),

  /// Recalled after some hesitation.
  good(3),

  /// Recalled effortlessly.
  easy(4);

  static FsrsRating fromValue(int value) {
    return switch (value) {
      1 => .again,
      2 => .hard,
      3 => .good,
      4 => .easy,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Rating value must be between 1 and 4',
      ),
    };
  }
}
