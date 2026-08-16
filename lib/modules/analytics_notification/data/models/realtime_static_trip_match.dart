import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';

enum RealtimeStaticTripMatchStatus {
  noTripId,
  noStaticTrip,
  routeMismatch,
  matchedWithoutStopTimes,
  matchedWithStopTimes,
}

class RealtimeStaticTripMatch {
  const RealtimeStaticTripMatch({
    required this.vehicle,
    required this.status,
    required this.staticTrip,
    required this.stopTimes,
  });

  final RealtimeVehicle vehicle;
  final RealtimeStaticTripMatchStatus status;
  final GtfsTrip? staticTrip;
  final List<GtfsStopTime> stopTimes;
}
