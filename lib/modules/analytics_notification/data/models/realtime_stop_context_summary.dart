import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_stop_context_result.dart';

class RealtimeStopContextSummary {
  RealtimeStopContextSummary({
    required Iterable<RealtimeStopContextResult> results,
  }) : results = List.unmodifiable(results);

  final List<RealtimeStopContextResult> results;

  int get eligibleMatchedVehicles => results.length;

  int get hasCurrentStopSequenceCount =>
      results.where((result) => result.hasCurrentStopSequence).length;

  int get noCurrentStopSequenceCount =>
      _count(RealtimeStopContextStatus.noCurrentStopSequence);

  int get sequenceMatchedCount =>
      _count(RealtimeStopContextStatus.sequenceMatched);

  int get sequenceNotFoundCount =>
      _count(RealtimeStopContextStatus.sequenceNotFoundInStaticStopTimes);

  int get hasRealtimeStopIdCount =>
      results.where((result) => result.hasRealtimeStopId).length;

  int get stopIdConsistentCount =>
      results.where((result) => result.stopIdConsistent).length;

  int get stopIdMismatchCount => results
      .where(
        (result) =>
            result.status == RealtimeStopContextStatus.sequenceMatched &&
            result.hasRealtimeStopId &&
            !result.stopIdConsistent,
      )
      .length;

  int get hasExplicitCurrentStatusCount =>
      results.where((result) => result.hasExplicitCurrentStatus).length;

  int get hasTimestampCount =>
      results.where((result) => result.hasVehicleTimestamp).length;

  int get vehiclesWithoutTimestamp =>
      eligibleMatchedVehicles - hasTimestampCount;

  double get sequenceCoveragePercentage =>
      _percentage(hasCurrentStopSequenceCount, eligibleMatchedVehicles);

  double get usableSequenceMatchPercentage =>
      _percentage(sequenceMatchedCount, eligibleMatchedVehicles);

  int _count(RealtimeStopContextStatus status) {
    return results.where((result) => result.status == status).length;
  }

  static double _percentage(int value, int total) {
    if (total == 0) {
      return 0;
    }
    return value / total * 100;
  }
}
