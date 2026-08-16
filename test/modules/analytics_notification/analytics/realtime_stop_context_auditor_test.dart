import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_stop_context_auditor.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_stop_context_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';

void main() {
  const auditor = RealtimeStopContextAuditor();

  test('matching sequence locates the static stop time', () {
    final summary = auditor.audit(
      _matchSummary([
        _eligibleMatch(_vehicle(currentStopSequence: 2), [
          _stopTime(sequence: 1),
          _stopTime(sequence: 2),
        ]),
      ]),
    );

    expect(
      summary.results.single.status,
      RealtimeStopContextStatus.sequenceMatched,
    );
    expect(summary.results.single.matchedStopTime?.stopSequence, 2);
  });

  test('missing sequence is noCurrentStopSequence', () {
    final summary = auditor.audit(
      _matchSummary([
        _eligibleMatch(_vehicle(currentStopSequence: null), [
          _stopTime(sequence: 1),
        ]),
      ]),
    );

    expect(
      summary.results.single.status,
      RealtimeStopContextStatus.noCurrentStopSequence,
    );
    expect(summary.noCurrentStopSequenceCount, 1);
  });

  test('unknown sequence is sequenceNotFoundInStaticStopTimes', () {
    final summary = auditor.audit(
      _matchSummary([
        _eligibleMatch(_vehicle(currentStopSequence: 9), [
          _stopTime(sequence: 1),
        ]),
      ]),
    );

    expect(
      summary.results.single.status,
      RealtimeStopContextStatus.sequenceNotFoundInStaticStopTimes,
    );
    expect(summary.sequenceNotFoundCount, 1);
  });

  test('equal realtime and static stop IDs are consistent', () {
    final summary = auditor.audit(
      _matchSummary([
        _eligibleMatch(_vehicle(currentStopSequence: 2, stopId: 'stop-2'), [
          _stopTime(sequence: 2, stopId: 'stop-2'),
        ]),
      ]),
    );

    expect(summary.results.single.stopIdConsistent, isTrue);
    expect(summary.stopIdConsistentCount, 1);
    expect(summary.stopIdMismatchCount, 0);
  });

  test('different realtime and static stop IDs are a mismatch', () {
    final summary = auditor.audit(
      _matchSummary([
        _eligibleMatch(
          _vehicle(currentStopSequence: 2, stopId: 'realtime-stop'),
          [_stopTime(sequence: 2, stopId: 'static-stop')],
        ),
      ]),
    );

    expect(summary.results.single.stopIdConsistent, isFalse);
    expect(summary.stopIdMismatchCount, 1);
  });

  test('missing realtime stop ID is not counted as a mismatch', () {
    final summary = auditor.audit(
      _matchSummary([
        _eligibleMatch(_vehicle(currentStopSequence: 2, stopId: null), [
          _stopTime(sequence: 2, stopId: 'static-stop'),
        ]),
      ]),
    );

    expect(summary.hasRealtimeStopIdCount, 0);
    expect(summary.stopIdConsistentCount, 0);
    expect(summary.stopIdMismatchCount, 0);
  });

  test('timestamp and explicit status availability are counted', () {
    final timestamp = DateTime.utc(2026, 8, 17, 10);
    final summary = auditor.audit(
      _matchSummary([
        _eligibleMatch(
          _vehicle(
            currentStopSequence: 1,
            timestamp: timestamp,
            currentStatus: RealtimeVehicleStopStatus.stoppedAt,
          ),
          [_stopTime(sequence: 1)],
        ),
        _eligibleMatch(_vehicle(currentStopSequence: null), [
          _stopTime(sequence: 1),
        ]),
      ]),
    );

    expect(summary.hasTimestampCount, 1);
    expect(summary.vehiclesWithoutTimestamp, 1);
    expect(summary.hasExplicitCurrentStatusCount, 1);
    expect(summary.sequenceCoveragePercentage, 50);
    expect(summary.usableSequenceMatchPercentage, 50);
  });

  test('only matchedWithStopTimes records are eligible', () {
    final summary = auditor.audit(
      _matchSummary([
        _matchWithStatus(RealtimeStaticTripMatchStatus.noTripId),
        _matchWithStatus(RealtimeStaticTripMatchStatus.noStaticTrip),
        _matchWithStatus(RealtimeStaticTripMatchStatus.routeMismatch),
        _matchWithStatus(RealtimeStaticTripMatchStatus.matchedWithoutStopTimes),
      ]),
    );

    expect(summary.eligibleMatchedVehicles, 0);
    expect(summary.results, isEmpty);
    expect(summary.sequenceCoveragePercentage, 0);
    expect(summary.usableSequenceMatchPercentage, 0);
  });

  test('empty trip match summary is safe', () {
    final summary = auditor.audit(_matchSummary(const []));

    expect(summary.eligibleMatchedVehicles, 0);
    expect(summary.hasTimestampCount, 0);
    expect(summary.stopIdMismatchCount, 0);
  });
}

RealtimeStaticTripMatchSummary _matchSummary(
  List<RealtimeStaticTripMatch> matches,
) {
  return RealtimeStaticTripMatchSummary(matches: matches);
}

RealtimeStaticTripMatch _eligibleMatch(
  RealtimeVehicle vehicle,
  List<GtfsStopTime> stopTimes,
) {
  return RealtimeStaticTripMatch(
    vehicle: vehicle,
    status: RealtimeStaticTripMatchStatus.matchedWithStopTimes,
    staticTrip: _trip,
    stopTimes: stopTimes,
  );
}

RealtimeStaticTripMatch _matchWithStatus(RealtimeStaticTripMatchStatus status) {
  return RealtimeStaticTripMatch(
    vehicle: _vehicle(currentStopSequence: 1),
    status: status,
    staticTrip:
        status == RealtimeStaticTripMatchStatus.noTripId ||
            status == RealtimeStaticTripMatchStatus.noStaticTrip
        ? null
        : _trip,
    stopTimes: status == RealtimeStaticTripMatchStatus.matchedWithoutStopTimes
        ? const []
        : [_stopTime(sequence: 1)],
  );
}

RealtimeVehicle _vehicle({
  required int? currentStopSequence,
  String? stopId,
  DateTime? timestamp,
  RealtimeVehicleStopStatus? currentStatus,
}) {
  return RealtimeVehicle(
    vehicleId: 'vehicle-1',
    tripId: 'trip-1',
    routeId: 'route-1',
    latitude: 3,
    longitude: 101,
    timestamp: timestamp,
    currentStopSequence: currentStopSequence,
    stopId: stopId,
    currentStatus: currentStatus,
  );
}

const _trip = GtfsTrip(
  routeId: 'route-1',
  serviceId: 'weekday',
  tripId: 'trip-1',
  tripHeadsign: null,
  directionId: null,
);

GtfsStopTime _stopTime({required int sequence, String? stopId}) {
  return GtfsStopTime(
    tripId: 'trip-1',
    arrivalTime: '10:00:00',
    departureTime: '10:01:00',
    stopId: stopId ?? 'stop-$sequence',
    stopSequence: sequence,
  );
}
