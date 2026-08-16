import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_route.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';

class GtfsStaticFeed {
  const GtfsStaticFeed({
    required this.routes,
    required this.trips,
    required this.stopTimes,
  });

  final List<GtfsRoute> routes;
  final List<GtfsTrip> trips;
  final List<GtfsStopTime> stopTimes;

  GtfsTrip? findTripById(String tripId) {
    for (final trip in trips) {
      if (trip.tripId == tripId) {
        return trip;
      }
    }
    return null;
  }

  List<GtfsStopTime> stopTimesForTrip(String tripId) {
    return List.unmodifiable(
      stopTimes.where((stopTime) => stopTime.tripId == tripId),
    );
  }
}
