import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';

enum RealtimeGpsStopLocalisationStatus {
  noCandidateStops,
  nearestScheduledStopFound,
}

enum RealtimeGpsStopDistanceBand {
  within100m,
  over100To250m,
  over250To500m,
  over500m,
}

class RealtimeGpsStopLocalisationResult {
  const RealtimeGpsStopLocalisationResult({
    required this.tripMatch,
    required this.nearestStop,
    required this.nearestStopTime,
    required this.distanceMeters,
    required this.candidateStopCount,
    required this.status,
  });

  final RealtimeStaticTripMatch tripMatch;
  final GtfsStop? nearestStop;
  final GtfsStopTime? nearestStopTime;
  final double? distanceMeters;
  final int candidateStopCount;
  final RealtimeGpsStopLocalisationStatus status;

  RealtimeGpsStopDistanceBand? get distanceBand {
    final distance = distanceMeters;
    if (distance == null) {
      return null;
    }
    if (distance <= 100) {
      return RealtimeGpsStopDistanceBand.within100m;
    }
    if (distance <= 250) {
      return RealtimeGpsStopDistanceBand.over100To250m;
    }
    if (distance <= 500) {
      return RealtimeGpsStopDistanceBand.over250To500m;
    }
    return RealtimeGpsStopDistanceBand.over500m;
  }
}
