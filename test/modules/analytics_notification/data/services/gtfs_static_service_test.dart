import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/gtfs_calendar_date.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_static_service.dart';

void main() {
  test('parses a valid route and a quoted name containing a comma', () {
    final routes = GtfsStaticService.parseRoutesCsv(
      'route_id,route_short_name,route_long_name,route_type\n'
      'route-1,R1,"City, Centre",3\n',
    );

    expect(routes, hasLength(1));
    expect(routes.single.routeId, 'route-1');
    expect(routes.single.routeShortName, 'R1');
    expect(routes.single.routeLongName, 'City, Centre');
    expect(routes.single.routeType, 3);
  });

  test('blank optional route names become null', () {
    final routes = GtfsStaticService.parseRoutesCsv(
      'route_id,route_short_name,route_long_name,route_type\n'
      'route-1,,,3\n',
    );

    expect(routes.single.routeShortName, isNull);
    expect(routes.single.routeLongName, isNull);
  });

  test('parses trips with optional headsign and direction', () {
    final trips = GtfsStaticService.parseTripsCsv(
      'route_id,service_id,trip_id,trip_headsign,direction_id\n'
      'route-1,weekday,trip-1,City Centre,1\n'
      'route-1,weekday,trip-2,,\n',
    );

    expect(trips, hasLength(2));
    expect(trips.first.tripHeadsign, 'City Centre');
    expect(trips.first.directionId, 1);
    expect(trips.last.tripHeadsign, isNull);
    expect(trips.last.directionId, isNull);
  });

  test('parses stop sequence and preserves a time above 24 hours', () {
    final stopTimes = GtfsStaticService.parseStopTimesCsv(
      'trip_id,arrival_time,departure_time,stop_id,stop_sequence\n'
      'trip-1,25:10:00,25:12:00,stop-1,7\n',
    );

    expect(stopTimes.single.arrivalTime, '25:10:00');
    expect(stopTimes.single.departureTime, '25:12:00');
    expect(stopTimes.single.stopSequence, 7);
  });

  test('parses a valid stop and a quoted name containing a comma', () {
    final stops = GtfsStaticService.parseStopsCsv(
      'stop_id,stop_name,stop_lat,stop_lon\n'
      'stop-1,"City, Centre",3.1390,101.6869\n',
    );

    expect(stops, hasLength(1));
    expect(stops.single.stopId, 'stop-1');
    expect(stops.single.stopName, 'City, Centre');
    expect(stops.single.stopLatitude, 3.1390);
    expect(stops.single.stopLongitude, 101.6869);
  });

  test('blank optional stop name is allowed', () {
    final stops = GtfsStaticService.parseStopsCsv(
      'stop_id,stop_name,stop_lat,stop_lon\n'
      'stop-1,,3.1390,101.6869\n',
    );

    expect(stops.single.stopName, isNull);
  });

  test('invalid and out-of-range stop coordinates are skipped safely', () {
    final stops = GtfsStaticService.parseStopsCsv(
      'stop_id,stop_name,stop_lat,stop_lon\n'
      'invalid-text,Text,not-a-number,101\n'
      'invalid-infinite,Infinite,Infinity,101\n'
      'invalid-lat,Latitude,91,101\n'
      'invalid-lon,Longitude,3,181\n'
      'valid,Valid,3,101\n',
    );

    expect(stops.map((stop) => stop.stopId), ['valid']);
  });

  test('agency timezone parses without hardcoding a timezone', () {
    final agencies = GtfsStaticService.parseAgencyCsv(
      'agency_id,agency_name,agency_timezone\n'
      'rapid-kl,Prasarana,Asia/Kuala_Lumpur\n',
    );

    expect(agencies.single.agencyId, 'rapid-kl');
    expect(agencies.single.agencyName, 'Prasarana');
    expect(agencies.single.agencyTimezone, 'Asia/Kuala_Lumpur');
  });

  test('calendar weekday flags and date range parse losslessly', () {
    final services = GtfsStaticService.parseCalendarCsv(_calendarCsv);

    expect(services.single.serviceId, 'weekday');
    expect(services.single.monday, isTrue);
    expect(services.single.friday, isTrue);
    expect(services.single.saturday, isFalse);
    expect(services.single.sunday, isFalse);
    expect(services.single.startDate, '20260101');
    expect(services.single.endDate, '20261231');
  });

  test('calendar-date added and removed exceptions parse distinctly', () {
    final dates = GtfsStaticService.parseCalendarDatesCsv(
      'service_id,date,exception_type\n'
      'weekday,20260817,1\n'
      'weekday,20260818,2\n',
    );

    expect(dates.map((date) => date.exceptionType), [
      GtfsCalendarDateExceptionType.serviceAdded,
      GtfsCalendarDateExceptionType.serviceRemoved,
    ]);
  });

  test(
    'frequency exact_times values remain distinct and times stay strings',
    () {
      final frequencies = GtfsStaticService.parseFrequenciesCsv(
        'trip_id,start_time,end_time,headway_secs,exact_times\n'
        'frequency-0,25:10:00,27:00:00,600,0\n'
        'frequency-1,06:00:00,09:00:00,900,1\n',
      );

      expect(frequencies.first.exactTimes, 0);
      expect(frequencies.first.isFrequencyBased, isTrue);
      expect(frequencies.first.startTime, '25:10:00');
      expect(frequencies.first.endTime, '27:00:00');
      expect(frequencies.last.exactTimes, 1);
      expect(frequencies.last.isScheduleBased, isTrue);
    },
  );

  test('extracts and parses all four required files from a ZIP', () {
    final feed = GtfsStaticService.parseArchiveBytes(_buildGtfsZip());

    expect(feed.routes, hasLength(1));
    expect(feed.trips, hasLength(2));
    expect(feed.stopTimes, hasLength(1));
    expect(feed.stops, hasLength(1));
    expect(feed.routes.single.routeId, 'route-1');
    expect(feed.findTripById('trip-1')?.routeId, 'route-1');
    expect(feed.stopsById['stop-1']?.stopName, 'City Centre');
    expect(feed.agencies, isEmpty);
    expect(feed.calendarServices, isEmpty);
    expect(feed.calendarDates, isEmpty);
    expect(feed.frequencies, isEmpty);
    expect(feed.hasAgencyFile, isFalse);
    expect(feed.hasCalendarFile, isFalse);
    expect(feed.hasCalendarDatesFile, isFalse);
    expect(feed.hasFrequenciesFile, isFalse);
  });

  test('missing stops.txt throws a clear exception', () {
    final zipWithoutStops = _buildGtfsZip(includeStops: false);

    expect(
      () => GtfsStaticService.parseArchiveBytes(zipWithoutStops),
      throwsA(
        isA<GtfsStaticException>().having(
          (error) => error.message,
          'message',
          contains('stops.txt'),
        ),
      ),
    );
  });

  test('stops.txt with zero valid records throws a clear exception', () {
    final archive = Archive()
      ..addFile(ArchiveFile.string('routes.txt', _routesCsv))
      ..addFile(ArchiveFile.string('trips.txt', _tripsCsv))
      ..addFile(ArchiveFile.string('stop_times.txt', _stopTimesCsv))
      ..addFile(
        ArchiveFile.string(
          'stops.txt',
          'stop_id,stop_name,stop_lat,stop_lon\ninvalid,Invalid,91,181\n',
        ),
      );

    expect(
      () => GtfsStaticService.parseArchiveBytes(ZipEncoder().encode(archive)),
      throwsA(
        isA<GtfsStaticException>().having(
          (error) => error.message,
          'message',
          contains('stops.txt contains no valid records'),
        ),
      ),
    );
  });

  test('missing a required GTFS file throws a clear exception', () {
    final zipWithoutStopTimes = _buildGtfsZip(includeStopTimes: false);

    expect(
      () => GtfsStaticService.parseArchiveBytes(zipWithoutStopTimes),
      throwsA(
        isA<GtfsStaticException>().having(
          (error) => error.message,
          'message',
          contains('stop_times.txt'),
        ),
      ),
    );
  });

  test('a trip without corresponding stop times remains valid', () {
    final feed = GtfsStaticService.parseArchiveBytes(_buildGtfsZip());

    expect(feed.findTripById('trip-without-stop-times'), isNotNull);
    expect(feed.stopTimesForTrip('trip-without-stop-times'), isEmpty);
  });

  test('calendar_dates works safely when calendar.txt is absent', () {
    final feed = GtfsStaticService.parseArchiveBytes(
      _buildGtfsZip(includeCalendarDates: true),
    );

    expect(feed.hasCalendarFile, isFalse);
    expect(feed.calendarServices, isEmpty);
    expect(feed.hasCalendarDatesFile, isTrue);
    expect(feed.calendarDates, hasLength(1));
    expect(feed.calendarDatesByServiceId['weekday'], hasLength(1));
  });

  test('optional frequencies.txt may be absent without failing parsing', () {
    final feed = GtfsStaticService.parseArchiveBytes(_buildGtfsZip());

    expect(feed.hasFrequenciesFile, isFalse);
    expect(feed.frequencies, isEmpty);
    expect(feed.frequenciesByTripId, isEmpty);
  });
}

const _routesCsv =
    'route_id,route_short_name,route_long_name,route_type\n'
    'route-1,R1,"City, Centre",3\n';
const _tripsCsv =
    'route_id,service_id,trip_id,trip_headsign,direction_id\n'
    'route-1,weekday,trip-1,City Centre,0\n'
    'route-1,weekday,trip-without-stop-times,,1\n';
const _stopTimesCsv =
    'trip_id,arrival_time,departure_time,stop_id,stop_sequence\n'
    'trip-1,25:10:00,25:12:00,stop-1,1\n';
const _stopsCsv =
    'stop_id,stop_name,stop_lat,stop_lon\n'
    'stop-1,City Centre,3.1390,101.6869\n';
const _calendarCsv =
    'service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,'
    'start_date,end_date\n'
    'weekday,1,1,1,1,1,0,0,20260101,20261231\n';
const _calendarDatesCsv =
    'service_id,date,exception_type\n'
    'weekday,20260817,1\n';

List<int> _buildGtfsZip({
  bool includeStopTimes = true,
  bool includeStops = true,
  bool includeCalendarDates = false,
}) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('routes.txt', _routesCsv))
    ..addFile(ArchiveFile.string('trips.txt', _tripsCsv));
  if (includeStopTimes) {
    archive.addFile(ArchiveFile.string('stop_times.txt', _stopTimesCsv));
  }
  if (includeStops) {
    archive.addFile(ArchiveFile.string('stops.txt', _stopsCsv));
  }
  if (includeCalendarDates) {
    archive.addFile(
      ArchiveFile.string('calendar_dates.txt', _calendarDatesCsv),
    );
  }
  return ZipEncoder().encode(archive);
}
