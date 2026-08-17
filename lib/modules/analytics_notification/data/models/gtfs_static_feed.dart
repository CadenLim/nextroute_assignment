import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_route.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';

class GtfsStaticFeed {
  GtfsStaticFeed({
    required this.routes,
    required this.trips,
    required this.stopTimes,
    required this.stops,
  }) : stopsById = Map.unmodifiable(_buildStopsById(stops));

  final List<GtfsRoute> routes;
  final List<GtfsTrip> trips;
  final List<GtfsStopTime> stopTimes;
  final List<GtfsStop> stops;
  final Map<String, GtfsStop> stopsById;

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

  static Map<String, GtfsStop> _buildStopsById(List<GtfsStop> stops) {
    final index = <String, GtfsStop>{};
    for (final stop in stops) {
      index.putIfAbsent(stop.stopId, () => stop);
    }
    return index;
  }
}
