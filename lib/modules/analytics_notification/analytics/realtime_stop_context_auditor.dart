import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_stop_context_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_stop_context_summary.dart';

class RealtimeStopContextAuditor {
  const RealtimeStopContextAuditor();

  RealtimeStopContextSummary audit(
    RealtimeStaticTripMatchSummary tripMatchSummary,
  ) {
    final results = <RealtimeStopContextResult>[];

    for (final tripMatch in tripMatchSummary.matches) {
      if (tripMatch.status !=
          RealtimeStaticTripMatchStatus.matchedWithStopTimes) {
        continue;
      }

      final vehicle = tripMatch.vehicle;
      final currentStopSequence = vehicle.currentStopSequence;
      GtfsStopTime? matchedStopTime;
      if (currentStopSequence != null) {
        for (final stopTime in tripMatch.stopTimes) {
          if (stopTime.stopSequence == currentStopSequence) {
            matchedStopTime = stopTime;
            break;
          }
        }
      }

      final contextStatus = currentStopSequence == null
          ? RealtimeStopContextStatus.noCurrentStopSequence
          : matchedStopTime == null
          ? RealtimeStopContextStatus.sequenceNotFoundInStaticStopTimes
          : RealtimeStopContextStatus.sequenceMatched;
      final realtimeStopId = vehicle.stopId;
      final hasRealtimeStopId =
          realtimeStopId != null && realtimeStopId.trim().isNotEmpty;
      final stopIdConsistent =
          matchedStopTime != null &&
          hasRealtimeStopId &&
          realtimeStopId == matchedStopTime.stopId;

      results.add(
        RealtimeStopContextResult(
          tripMatch: tripMatch,
          matchedStopTime: matchedStopTime,
          status: contextStatus,
          hasCurrentStopSequence: currentStopSequence != null,
          hasRealtimeStopId: hasRealtimeStopId,
          hasVehicleTimestamp: vehicle.timestamp != null,
          hasExplicitCurrentStatus: vehicle.currentStatus != null,
          stopIdConsistent: stopIdConsistent,
        ),
      );
    }

    return RealtimeStopContextSummary(results: results);
  }
}
