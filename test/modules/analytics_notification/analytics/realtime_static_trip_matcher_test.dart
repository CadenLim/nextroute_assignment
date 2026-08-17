import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_static_trip_matcher.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';

void main() {
  const matcher = RealtimeStaticTripMatcher();

  test('missing realtime trip ID is noTripId', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([_vehicle(tripId: null)]),
      staticFeed: _staticFeed(),
    );

    expect(
      summary.matches.single.status,
      RealtimeStaticTripMatchStatus.noTripId,
    );
  });

  test('unknown exact trip ID is noStaticTrip', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([_vehicle(tripId: 'unknown-trip')]),
      staticFeed: _staticFeed(trips: [_trip('known-trip')]),
    );

    expect(
      summary.matches.single.status,
      RealtimeStaticTripMatchStatus.noStaticTrip,
    );
  });

  test('does not apply prefix or fuzzy trip matching', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([_vehicle(tripId: 'prefix-trip-1')]),
      staticFeed: _staticFeed(trips: [_trip('trip-1')]),
    );

    expect(
      summary.matches.single.status,
      RealtimeStaticTripMatchStatus.noStaticTrip,
    );
  });

  test('exact trip match with stop times is matchedWithStopTimes', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([_vehicle(tripId: 'trip-1')]),
      staticFeed: _staticFeed(
        trips: [_trip('trip-1')],
        stopTimes: [_stopTime('trip-1', sequence: 1)],
      ),
    );

    expect(
      summary.matches.single.status,
      RealtimeStaticTripMatchStatus.matchedWithStopTimes,
    );
  });

  test('exact trip match without stop times is matchedWithoutStopTimes', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([_vehicle(tripId: 'trip-1')]),
      staticFeed: _staticFeed(trips: [_trip('trip-1')]),
    );

    expect(
      summary.matches.single.status,
      RealtimeStaticTripMatchStatus.matchedWithoutStopTimes,
    );
    expect(summary.matches.single.stopTimes, isEmpty);
  });

  test('different available route IDs produce routeMismatch', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([
        _vehicle(tripId: 'trip-1', routeId: 'realtime-route'),
      ]),
      staticFeed: _staticFeed(
        trips: [_trip('trip-1', routeId: 'static-route')],
      ),
    );

    expect(
      summary.matches.single.status,
      RealtimeStaticTripMatchStatus.routeMismatch,
    );
  });

  test('missing realtime route ID is not a route mismatch', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([_vehicle(tripId: 'trip-1', routeId: null)]),
      staticFeed: _staticFeed(
        trips: [_trip('trip-1', routeId: 'static-route')],
      ),
    );

    expect(
      summary.matches.single.status,
      RealtimeStaticTripMatchStatus.matchedWithoutStopTimes,
    );
  });

  test('matched stop times are ordered by stopSequence', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([_vehicle(tripId: 'trip-1')]),
      staticFeed: _staticFeed(
        trips: [_trip('trip-1')],
        stopTimes: [
          _stopTime('trip-1', sequence: 3),
          _stopTime('trip-1', sequence: 1),
          _stopTime('trip-1', sequence: 2),
        ],
      ),
    );

    expect(
      summary.matches.single.stopTimes.map((stopTime) => stopTime.stopSequence),
      [1, 2, 3],
    );
  });

  test('mutually exclusive summary counts equal total vehicles', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed([
        _vehicle(tripId: null),
        _vehicle(tripId: 'unknown'),
        _vehicle(tripId: 'with-stops'),
        _vehicle(tripId: 'without-stops'),
        _vehicle(tripId: 'mismatch', routeId: 'realtime-route'),
      ]),
      staticFeed: _staticFeed(
        trips: [
          _trip('with-stops'),
          _trip('without-stops'),
          _trip('mismatch', routeId: 'static-route'),
        ],
        stopTimes: [_stopTime('with-stops', sequence: 1)],
      ),
    );

    final statusTotal =
        summary.noTripIdCount +
        summary.noStaticTripCount +
        summary.routeMismatchCount +
        summary.matchedWithoutStopTimesCount +
        summary.matchedWithStopTimesCount;
    expect(statusTotal, summary.totalRealtimeVehicles);
    expect(summary.totalRealtimeVehicles, 5);
    expect(summary.exactMatchedCount, 3);
    expect(summary.vehiclesWithTripIdCount, 4);
    expect(summary.exactMatchPercentage, 75);
  });

  test('empty realtime feed produces a safe empty summary', () {
    final summary = matcher.match(
      realtimeFeed: _realtimeFeed(const []),
      staticFeed: _staticFeed(),
    );

    expect(summary.totalRealtimeVehicles, 0);
    expect(summary.matches, isEmpty);
    expect(summary.exactMatchPercentage, 0);
  });
}

VehiclePositionFeed _realtimeFeed(List<RealtimeVehicle> vehicles) {
  return VehiclePositionFeed(
    totalEntities: vehicles.length,
    vehicles: vehicles,
  );
}

GtfsStaticFeed _staticFeed({
  List<GtfsTrip> trips = const [],
  List<GtfsStopTime> stopTimes = const [],
}) {
  return GtfsStaticFeed(
    routes: const [],
    trips: trips,
    stopTimes: stopTimes,
    stops: const [],
  );
}

RealtimeVehicle _vehicle({
  required String? tripId,
  String? routeId = 'route-1',
}) {
  return RealtimeVehicle(
    vehicleId: 'vehicle-1',
    tripId: tripId,
    routeId: routeId,
    latitude: 3,
    longitude: 101,
    timestamp: null,
  );
}

GtfsTrip _trip(String tripId, {String routeId = 'route-1'}) {
  return GtfsTrip(
    routeId: routeId,
    serviceId: 'weekday',
    tripId: tripId,
    tripHeadsign: null,
    directionId: null,
  );
}

GtfsStopTime _stopTime(String tripId, {required int sequence}) {
  return GtfsStopTime(
    tripId: tripId,
    arrivalTime: '10:00:00',
    departureTime: '10:01:00',
    stopId: 'stop-$sequence',
    stopSequence: sequence,
  );
}
