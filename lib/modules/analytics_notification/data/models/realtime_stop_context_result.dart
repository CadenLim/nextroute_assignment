import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';

enum RealtimeStopContextStatus {
  noCurrentStopSequence,
  sequenceNotFoundInStaticStopTimes,
  sequenceMatched,
}

class RealtimeStopContextResult {
  const RealtimeStopContextResult({
    required this.tripMatch,
    required this.matchedStopTime,
    required this.status,
    required this.hasCurrentStopSequence,
    required this.hasRealtimeStopId,
    required this.hasVehicleTimestamp,
    required this.hasExplicitCurrentStatus,
    required this.stopIdConsistent,
  });

  final RealtimeStaticTripMatch tripMatch;
  final GtfsStopTime? matchedStopTime;
  final RealtimeStopContextStatus status;
  final bool hasCurrentStopSequence;
  final bool hasRealtimeStopId;
  final bool hasVehicleTimestamp;
  final bool hasExplicitCurrentStatus;
  final bool stopIdConsistent;
}
