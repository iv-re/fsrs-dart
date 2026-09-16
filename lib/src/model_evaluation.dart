import 'package:meta/meta.dart';

/// Evaluation metrics of an FSRS model on a training set.
@immutable
final class const FsrsModelEvaluation({
  /// Binary cross-entropy assessing probability accuracy (lower is better).
  required final double logLoss,

  /// Calibration error across retention bins (lower is better).
  required final double rmseBins,
}) {
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FsrsModelEvaluation &&
          runtimeType == other.runtimeType &&
          logLoss == other.logLoss &&
          rmseBins == other.rmseBins;

  @override
  int get hashCode => Object.hash(logLoss, rmseBins);

  @override
  String toString() =>
      'FsrsModelEvaluation(logLoss: $logLoss, rmseBins: $rmseBins)';
}
