import 'dart:math' as math;

import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_gps_stop_localisation_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_gps_stop_localisation_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match_summary.dart';

class RealtimeGpsStopLocaliser {
  const RealtimeGpsStopLocaliser();

  static const double earthRadiusMeters = 6371000;

  RealtimeGpsStopLocalisationSummary localise({
    required RealtimeStaticTripMatchSummary tripMatchSummary,
    required GtfsStaticFeed staticFeed,
  }) {
    final results = <RealtimeGpsStopLocalisationResult>[];

    for (final tripMatch in tripMatchSummary.matches) {
      if (tripMatch.status !=
          RealtimeStaticTripMatchStatus.matchedWithStopTimes) {
        continue;
      }

      final vehicle = tripMatch.vehicle;
      GtfsStop? nearestStop;
      GtfsStopTime? nearestStopTime;
      double? nearestDistance;
      var candidateStopCount = 0;

      for (final stopTime in tripMatch.stopTimes) {
        final stop = staticFeed.stopsById[stopTime.stopId];
        if (stop == null) {
          continue;
        }
        candidateStopCount += 1;

        final distance = distanceBetweenMeters(
          latitude1: vehicle.latitude,
          longitude1: vehicle.longitude,
          latitude2: stop.stopLatitude,
          longitude2: stop.stopLongitude,
        );
        final isCloser = nearestDistance == null || distance < nearestDistance;
        final isEqualButEarlierInTrip =
            nearestDistance != null &&
            distance == nearestDistance &&
            (nearestStopTime == null ||
                stopTime.stopSequence < nearestStopTime.stopSequence);
        if (isCloser || isEqualButEarlierInTrip) {
          nearestStop = stop;
          nearestStopTime = stopTime;
          nearestDistance = distance;
        }
      }

      results.add(
        RealtimeGpsStopLocalisationResult(
          tripMatch: tripMatch,
          nearestStop: nearestStop,
          nearestStopTime: nearestStopTime,
          distanceMeters: nearestDistance,
          candidateStopCount: candidateStopCount,
          status: nearestStop == null
              ? RealtimeGpsStopLocalisationStatus.noCandidateStops
              : RealtimeGpsStopLocalisationStatus.nearestScheduledStopFound,
        ),
      );
    }

    return RealtimeGpsStopLocalisationSummary(results: results);
  }

  double distanceBetweenMeters({
    required double latitude1,
    required double longitude1,
    required double latitude2,
    required double longitude2,
  }) {
    final latitudeDelta = _degreesToRadians(latitude2 - latitude1);
    final longitudeDelta = _degreesToRadians(longitude2 - longitude1);
    final firstLatitude = _degreesToRadians(latitude1);
    final secondLatitude = _degreesToRadians(latitude2);

    final sinLatitude = math.sin(latitudeDelta / 2);
    final sinLongitude = math.sin(longitudeDelta / 2);
    final haversine =
        sinLatitude * sinLatitude +
        math.cos(firstLatitude) *
            math.cos(secondLatitude) *
            sinLongitude *
            sinLongitude;
    final clampedHaversine = haversine.clamp(0.0, 1.0);
    final centralAngle =
        2 *
        math.atan2(
          math.sqrt(clampedHaversine),
          math.sqrt(1 - clampedHaversine),
        );
    return earthRadiusMeters * centralAngle;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * math.pi / 180;
  }
}
