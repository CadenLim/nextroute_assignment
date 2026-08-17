import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_gps_stop_localiser.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_gps_stop_localisation_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_gps_stop_localisation_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';

void main() {
  const localiser = RealtimeGpsStopLocaliser();

  test('only considers stops referenced by the matched trip', () {
    final tripStop = _stop('trip-stop', latitude: 0, longitude: 0.01);
    final unrelatedCloserStop = _stop(
      'unrelated-stop',
      latitude: 0,
      longitude: 0,
    );
    final summary = localiser.localise(
      tripMatchSummary: _matchSummary([
        _eligibleMatch(stopTimes: [_stopTime('trip-stop', sequence: 1)]),
      ]),
      staticFeed: _feed(stops: [tripStop, unrelatedCloserStop]),
    );

    expect(summary.results.single.nearestStop?.stopId, 'trip-stop');
    expect(summary.results.single.candidateStopCount, 1);
  });

  test('selects the nearest scheduled stop from multiple candidates', () {
    final summary = localiser.localise(
      tripMatchSummary: _matchSummary([
        _eligibleMatch(
          stopTimes: [
            _stopTime('far', sequence: 1),
            _stopTime('near', sequence: 2),
          ],
        ),
      ]),
      staticFeed: _feed(
        stops: [
          _stop('far', latitude: 0, longitude: 0.02),
          _stop('near', latitude: 0, longitude: 0.001),
        ],
      ),
    );

    final result = summary.results.single;
    expect(
      result.status,
      RealtimeGpsStopLocalisationStatus.nearestScheduledStopFound,
    );
    expect(result.nearestStop?.stopId, 'near');
    expect(result.nearestStopTime?.stopSequence, 2);
    expect(result.nearestStopTime?.arrivalTime, '10:02:00');
    expect(result.nearestStopTime?.departureTime, '10:03:00');
  });

  test('missing one static stop coordinate record is skipped safely', () {
    final summary = localiser.localise(
      tripMatchSummary: _matchSummary([
        _eligibleMatch(
          stopTimes: [
            _stopTime('missing', sequence: 1),
            _stopTime('available', sequence: 2),
          ],
        ),
      ]),
      staticFeed: _feed(
        stops: [_stop('available', latitude: 0, longitude: 0.001)],
      ),
    );

    final result = summary.results.single;
    expect(result.nearestStop?.stopId, 'available');
    expect(result.candidateStopCount, 1);
  });

  test('zero usable trip candidates returns noCandidateStops', () {
    final summary = localiser.localise(
      tripMatchSummary: _matchSummary([
        _eligibleMatch(stopTimes: [_stopTime('missing', sequence: 1)]),
      ]),
      staticFeed: _feed(stops: const []),
    );

    final result = summary.results.single;
    expect(result.status, RealtimeGpsStopLocalisationStatus.noCandidateStops);
    expect(result.nearestStop, isNull);
    expect(result.nearestStopTime, isNull);
    expect(result.distanceMeters, isNull);
    expect(result.candidateStopCount, 0);
  });

  test('repeated stop ID retains deterministic stop-sequence context', () {
    final summary = localiser.localise(
      tripMatchSummary: _matchSummary([
        _eligibleMatch(
          stopTimes: [
            _stopTime('repeated', sequence: 8),
            _stopTime('repeated', sequence: 3),
          ],
        ),
      ]),
      staticFeed: _feed(
        stops: [_stop('repeated', latitude: 0, longitude: 0.001)],
      ),
    );

    final result = summary.results.single;
    expect(result.candidateStopCount, 2);
    expect(result.nearestStop?.stopId, 'repeated');
    expect(result.nearestStopTime?.stopSequence, 3);
  });

  test('Haversine distance is sensible for deterministic coordinates', () {
    final distance = localiser.distanceBetweenMeters(
      latitude1: 0,
      longitude1: 0,
      latitude2: 0,
      longitude2: 0.001,
    );

    expect(distance, closeTo(111.195, 0.01));
    expect(
      localiser.distanceBetweenMeters(
        latitude1: 3.1390,
        longitude1: 101.6869,
        latitude2: 3.1390,
        longitude2: 101.6869,
      ),
      0,
    );
  });

  test(
    'distance bands are mutually exclusive and total successful results',
    () {
      final results = [
        _resultAtDistance(100),
        _resultAtDistance(100.01),
        _resultAtDistance(250),
        _resultAtDistance(250.01),
        _resultAtDistance(500),
        _resultAtDistance(500.01),
        _noCandidateResult(),
      ];
      final summary = RealtimeGpsStopLocalisationSummary(results: results);

      expect(summary.within100mCount, 1);
      expect(summary.over100To250mCount, 2);
      expect(summary.over250To500mCount, 2);
      expect(summary.over500mCount, 1);
      expect(summary.nearestScheduledStopFoundCount, 6);
      expect(summary.noCandidateStopsCount, 1);
      expect(summary.distanceBandTotal, summary.nearestScheduledStopFoundCount);
      expect(summary.localisationCoveragePercentage, closeTo(85.714, 0.001));
    },
  );

  test('only matchedWithStopTimes vehicles are eligible', () {
    final summary = localiser.localise(
      tripMatchSummary: _matchSummary([
        for (final status in RealtimeStaticTripMatchStatus.values)
          if (status != RealtimeStaticTripMatchStatus.matchedWithStopTimes)
            _matchWithStatus(status),
      ]),
      staticFeed: _feed(stops: const []),
    );

    expect(summary.eligibleMatchedVehicles, 0);
    expect(summary.results, isEmpty);
    expect(summary.localisationCoveragePercentage, 0);
  });

  test('empty eligible population is safe', () {
    final summary = localiser.localise(
      tripMatchSummary: _matchSummary(const []),
      staticFeed: _feed(stops: const []),
    );

    expect(summary.eligibleMatchedVehicles, 0);
    expect(summary.nearestScheduledStopFoundCount, 0);
    expect(summary.noCandidateStopsCount, 0);
    expect(summary.distanceBandTotal, 0);
    expect(summary.localisationCoveragePercentage, 0);
  });
}

GtfsStaticFeed _feed({required List<GtfsStop> stops}) {
  return GtfsStaticFeed(
    routes: const [],
    trips: const [_trip],
    stopTimes: const [],
    stops: stops,
  );
}

RealtimeStaticTripMatchSummary _matchSummary(
  List<RealtimeStaticTripMatch> matches,
) {
  return RealtimeStaticTripMatchSummary(matches: matches);
}

RealtimeStaticTripMatch _eligibleMatch({
  required List<GtfsStopTime> stopTimes,
}) {
  return RealtimeStaticTripMatch(
    vehicle: _vehicle,
    status: RealtimeStaticTripMatchStatus.matchedWithStopTimes,
    staticTrip: _trip,
    stopTimes: stopTimes,
  );
}

RealtimeStaticTripMatch _matchWithStatus(RealtimeStaticTripMatchStatus status) {
  return RealtimeStaticTripMatch(
    vehicle: _vehicle,
    status: status,
    staticTrip:
        status == RealtimeStaticTripMatchStatus.noTripId ||
            status == RealtimeStaticTripMatchStatus.noStaticTrip
        ? null
        : _trip,
    stopTimes: status == RealtimeStaticTripMatchStatus.matchedWithoutStopTimes
        ? const []
        : [_stopTime('stop-1', sequence: 1)],
  );
}

GtfsStop _stop(
  String stopId, {
  required double latitude,
  required double longitude,
}) {
  return GtfsStop(
    stopId: stopId,
    stopName: 'Stop $stopId',
    stopLatitude: latitude,
    stopLongitude: longitude,
  );
}

GtfsStopTime _stopTime(String stopId, {required int sequence}) {
  return GtfsStopTime(
    tripId: 'trip-1',
    arrivalTime: '10:${sequence.toString().padLeft(2, '0')}:00',
    departureTime: '10:${(sequence + 1).toString().padLeft(2, '0')}:00',
    stopId: stopId,
    stopSequence: sequence,
  );
}

RealtimeGpsStopLocalisationResult _resultAtDistance(double distance) {
  final stop = _stop('stop-$distance', latitude: 0, longitude: 0);
  return RealtimeGpsStopLocalisationResult(
    tripMatch: _eligibleMatch(stopTimes: [_stopTime(stop.stopId, sequence: 1)]),
    nearestStop: stop,
    nearestStopTime: _stopTime(stop.stopId, sequence: 1),
    distanceMeters: distance,
    candidateStopCount: 1,
    status: RealtimeGpsStopLocalisationStatus.nearestScheduledStopFound,
  );
}

RealtimeGpsStopLocalisationResult _noCandidateResult() {
  return RealtimeGpsStopLocalisationResult(
    tripMatch: _eligibleMatch(stopTimes: [_stopTime('missing', sequence: 1)]),
    nearestStop: null,
    nearestStopTime: null,
    distanceMeters: null,
    candidateStopCount: 0,
    status: RealtimeGpsStopLocalisationStatus.noCandidateStops,
  );
}

const _trip = GtfsTrip(
  routeId: 'route-1',
  serviceId: 'weekday',
  tripId: 'trip-1',
  tripHeadsign: null,
  directionId: null,
);

const _vehicle = RealtimeVehicle(
  vehicleId: 'vehicle-1',
  tripId: 'trip-1',
  routeId: 'route-1',
  latitude: 0,
  longitude: 0,
  timestamp: null,
);
