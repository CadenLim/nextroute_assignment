import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_trip_instance_auditor.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_agency.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_calendar_date.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_calendar_service.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_frequency.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_static_feed.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_stop_time.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_trip.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_static_trip_match_summary.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_trip_instance_audit_result.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';

void main() {
  const auditor = RealtimeTripInstanceAuditor();

  test('trip present in frequencies is classified as frequency-defined', () {
    final summary = auditor.audit(
      tripMatchSummary: _matchSummary([
        _eligibleMatch(_vehicle(startTime: '06:00:00', startDate: '20260817')),
      ]),
      staticFeed: _feed(frequencies: const [_frequency]),
    );

    final result = summary.results.single;
    expect(result.isFrequencyDefinedTrip, isTrue);
    expect(result.frequencyEntries.single.exactTimes, 0);
    expect(
      result.status,
      RealtimeTripInstanceAuditStatus.frequencyTripWithInstanceMetadata,
    );
  });

  test('all static frequency periods remain available for one trip', () {
    final summary = auditor.audit(
      tripMatchSummary: _matchSummary([
        _eligibleMatch(_vehicle(startTime: '06:00:00', startDate: '20260817')),
      ]),
      staticFeed: _feed(frequencies: const [_frequency, _laterFrequency]),
    );

    final entries = summary.results.single.frequencyEntries;
    expect(entries, hasLength(2));
    expect(entries.map((entry) => entry.startTime), ['25:00:00', '28:00:00']);
    expect(entries.map((entry) => entry.endTime), ['27:00:00', '30:00:00']);
    expect(entries.map((entry) => entry.headwaySecs), [600, 900]);
    expect(entries.map((entry) => entry.exactTimes), [0, 1]);
  });

  test('trip absent from frequencies is classified as fixed-schedule', () {
    final summary = auditor.audit(
      tripMatchSummary: _matchSummary([_eligibleMatch(_vehicle())]),
      staticFeed: _feed(),
    );

    expect(
      summary.results.single.status,
      RealtimeTripInstanceAuditStatus.fixedScheduleTrip,
    );
    expect(summary.frequencyDefinedTripCount, 0);
    expect(summary.fixedScheduleTripCount, 1);
  });

  test(
    'frequency instance requires both realtime start time and start date',
    () {
      final summary = auditor.audit(
        tripMatchSummary: _matchSummary([
          _eligibleMatch(
            _vehicle(startTime: '06:00:00', startDate: '20260817'),
          ),
          _eligibleMatch(_vehicle(startTime: '06:00:00')),
          _eligibleMatch(_vehicle(startDate: '20260817')),
        ]),
        staticFeed: _feed(frequencies: const [_frequency]),
      );

      expect(summary.frequencyDefinedTripCount, 3);
      expect(summary.frequencyTripWithInstanceMetadataCount, 1);
      expect(summary.frequencyTripMissingInstanceMetadataCount, 2);
      expect(summary.realtimeStartTimeProvidedCount, 2);
      expect(summary.realtimeStartDateProvidedCount, 2);
    },
  );

  test('audits agency, calendar service, and calendar-date availability', () {
    final summary = auditor.audit(
      tripMatchSummary: _matchSummary([
        _eligibleMatch(
          _vehicle(
            scheduleRelationship: RealtimeTripScheduleRelationship.scheduled,
          ),
        ),
      ]),
      staticFeed: _feed(
        agencies: const [_agency],
        calendarServices: const [_calendarService],
        calendarDates: const [_calendarDate],
      ),
    );

    final result = summary.results.single;
    expect(result.agencyTimezone, 'Asia/Kuala_Lumpur');
    expect(result.hasAgencyTimezone, isTrue);
    expect(result.hasCalendarService, isTrue);
    expect(result.hasCalendarDateMetadata, isTrue);
    expect(result.hasExplicitScheduleRelationship, isTrue);
    expect(summary.agencyTimezoneAvailableCount, 1);
    expect(summary.calendarServiceMetadataAvailableCount, 1);
    expect(summary.calendarServiceMetadataMissingCount, 0);
    expect(summary.calendarDateMetadataAvailableCount, 1);
    expect(summary.explicitScheduleRelationshipProvidedCount, 1);
  });

  test('missing calendar service metadata is counted safely', () {
    final summary = auditor.audit(
      tripMatchSummary: _matchSummary([_eligibleMatch(_vehicle())]),
      staticFeed: _feed(calendarDates: const [_calendarDate]),
    );

    expect(summary.calendarServiceMetadataAvailableCount, 0);
    expect(summary.calendarServiceMetadataMissingCount, 1);
    expect(summary.results.single.hasCalendarDateMetadata, isTrue);
  });

  test('only matchedWithStopTimes vehicles are eligible', () {
    final summary = auditor.audit(
      tripMatchSummary: _matchSummary([
        for (final status in RealtimeStaticTripMatchStatus.values)
          if (status != RealtimeStaticTripMatchStatus.matchedWithStopTimes)
            _matchWithStatus(status),
      ]),
      staticFeed: _feed(),
    );

    expect(summary.eligibleMatchedVehicles, 0);
    expect(summary.results, isEmpty);
  });

  test('empty matched population is safe', () {
    final summary = auditor.audit(
      tripMatchSummary: _matchSummary(const []),
      staticFeed: _feed(),
    );

    expect(summary.eligibleMatchedVehicles, 0);
    expect(summary.fixedScheduleTripCount, 0);
    expect(summary.calendarServiceMetadataMissingCount, 0);
  });
}

GtfsStaticFeed _feed({
  List<GtfsAgency> agencies = const [],
  List<GtfsCalendarService> calendarServices = const [],
  List<GtfsCalendarDate> calendarDates = const [],
  List<GtfsFrequency> frequencies = const [],
}) {
  return GtfsStaticFeed(
    routes: const [],
    trips: const [_trip],
    stopTimes: const [_stopTime],
    stops: const [],
    agencies: agencies,
    calendarServices: calendarServices,
    calendarDates: calendarDates,
    frequencies: frequencies,
  );
}

RealtimeStaticTripMatchSummary _matchSummary(
  List<RealtimeStaticTripMatch> matches,
) {
  return RealtimeStaticTripMatchSummary(matches: matches);
}

RealtimeStaticTripMatch _eligibleMatch(RealtimeVehicle vehicle) {
  return RealtimeStaticTripMatch(
    vehicle: vehicle,
    status: RealtimeStaticTripMatchStatus.matchedWithStopTimes,
    staticTrip: _trip,
    stopTimes: const [_stopTime],
  );
}

RealtimeStaticTripMatch _matchWithStatus(RealtimeStaticTripMatchStatus status) {
  return RealtimeStaticTripMatch(
    vehicle: _vehicle(),
    status: status,
    staticTrip:
        status == RealtimeStaticTripMatchStatus.noTripId ||
            status == RealtimeStaticTripMatchStatus.noStaticTrip
        ? null
        : _trip,
    stopTimes: status == RealtimeStaticTripMatchStatus.matchedWithoutStopTimes
        ? const []
        : const [_stopTime],
  );
}

RealtimeVehicle _vehicle({
  String? startTime,
  String? startDate,
  RealtimeTripScheduleRelationship? scheduleRelationship,
}) {
  return RealtimeVehicle(
    vehicleId: 'vehicle-1',
    tripId: 'trip-1',
    routeId: 'route-1',
    latitude: 3,
    longitude: 101,
    timestamp: null,
    tripStartTime: startTime,
    tripStartDate: startDate,
    scheduleRelationship: scheduleRelationship,
  );
}

const _trip = GtfsTrip(
  routeId: 'route-1',
  serviceId: 'weekday',
  tripId: 'trip-1',
  tripHeadsign: null,
  directionId: null,
);

const _stopTime = GtfsStopTime(
  tripId: 'trip-1',
  arrivalTime: '25:10:00',
  departureTime: '25:11:00',
  stopId: 'stop-1',
  stopSequence: 1,
);

const _frequency = GtfsFrequency(
  tripId: 'trip-1',
  startTime: '25:00:00',
  endTime: '27:00:00',
  headwaySecs: 600,
  exactTimes: 0,
);

const _laterFrequency = GtfsFrequency(
  tripId: 'trip-1',
  startTime: '28:00:00',
  endTime: '30:00:00',
  headwaySecs: 900,
  exactTimes: 1,
);

const _agency = GtfsAgency(
  agencyId: 'rapid-kl',
  agencyName: 'Prasarana',
  agencyTimezone: 'Asia/Kuala_Lumpur',
);

const _calendarService = GtfsCalendarService(
  serviceId: 'weekday',
  monday: true,
  tuesday: true,
  wednesday: true,
  thursday: true,
  friday: true,
  saturday: false,
  sunday: false,
  startDate: '20260101',
  endDate: '20261231',
);

const _calendarDate = GtfsCalendarDate(
  serviceId: 'weekday',
  date: '20260817',
  exceptionType: GtfsCalendarDateExceptionType.serviceAdded,
);
