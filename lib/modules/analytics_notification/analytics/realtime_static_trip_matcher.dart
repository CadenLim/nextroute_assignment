import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';

class RealtimeStaticTripMatcher {
  const RealtimeStaticTripMatcher();

  RealtimeStaticTripMatchSummary match({
    required VehiclePositionFeed realtimeFeed,
    required GtfsStaticFeed staticFeed,
  }) {
    final tripsById = <String, GtfsTrip>{};
    for (final trip in staticFeed.trips) {
      tripsById.putIfAbsent(trip.tripId, () => trip);
    }

    final stopTimesByTripId = <String, List<GtfsStopTime>>{};
    for (final stopTime in staticFeed.stopTimes) {
      stopTimesByTripId.putIfAbsent(stopTime.tripId, () => []).add(stopTime);
    }
    for (final stopTimes in stopTimesByTripId.values) {
      stopTimes.sort(
        (first, second) => first.stopSequence.compareTo(second.stopSequence),
      );
    }

    final matches = realtimeFeed.vehicles.map((vehicle) {
      final realtimeTripId = vehicle.tripId;
      if (realtimeTripId == null || realtimeTripId.trim().isEmpty) {
        return RealtimeStaticTripMatch(
          vehicle: vehicle,
          status: RealtimeStaticTripMatchStatus.noTripId,
          staticTrip: null,
          stopTimes: const [],
        );
      }

      final staticTrip = tripsById[realtimeTripId];
      if (staticTrip == null) {
        return RealtimeStaticTripMatch(
          vehicle: vehicle,
          status: RealtimeStaticTripMatchStatus.noStaticTrip,
          staticTrip: null,
          stopTimes: const [],
        );
      }

      final stopTimes = List<GtfsStopTime>.unmodifiable(
        stopTimesByTripId[realtimeTripId] ?? const [],
      );
      final realtimeRouteId = vehicle.routeId;
      if (_hasValue(realtimeRouteId) &&
          _hasValue(staticTrip.routeId) &&
          realtimeRouteId != staticTrip.routeId) {
        return RealtimeStaticTripMatch(
          vehicle: vehicle,
          status: RealtimeStaticTripMatchStatus.routeMismatch,
          staticTrip: staticTrip,
          stopTimes: stopTimes,
        );
      }

      return RealtimeStaticTripMatch(
        vehicle: vehicle,
        status: stopTimes.isEmpty
            ? RealtimeStaticTripMatchStatus.matchedWithoutStopTimes
            : RealtimeStaticTripMatchStatus.matchedWithStopTimes,
        staticTrip: staticTrip,
        stopTimes: stopTimes,
      );
    });

    return RealtimeStaticTripMatchSummary(matches: matches);
  }

  static bool _hasValue(String? value) {
    return value != null && value.trim().isNotEmpty;
  }
}
