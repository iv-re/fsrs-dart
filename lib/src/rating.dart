/// Performance rating given during a review.
enum const FsrsRating(final int value) {
  /// Manual override or administrative action (not a standard review grade).
  manual(0),
  again(1),
  hard(2),
  good(3),
  easy(4);

  /// Whether this rating represents an active review grade.
  bool get isGrade => this != manual;

  static FsrsRating fromValue(int value) {
    return switch (value) {
      0 => .manual,
      1 => .again,
      2 => .hard,
      3 => .good,
      4 => .easy,
      _ => throw ArgumentError.value(
        value,
        'value',
        'Rating value must be between 0 and 4',
      ),
    };
  }
}
