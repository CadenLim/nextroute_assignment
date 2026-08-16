import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
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

  test('extracts and parses all three required files from a ZIP', () {
    final feed = GtfsStaticService.parseArchiveBytes(_buildGtfsZip());

    expect(feed.routes, hasLength(1));
    expect(feed.trips, hasLength(2));
    expect(feed.stopTimes, hasLength(1));
    expect(feed.routes.single.routeId, 'route-1');
    expect(feed.findTripById('trip-1')?.routeId, 'route-1');
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
}

List<int> _buildGtfsZip({bool includeStopTimes = true}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string(
        'routes.txt',
        'route_id,route_short_name,route_long_name,route_type\n'
            'route-1,R1,"City, Centre",3\n',
      ),
    )
    ..addFile(
      ArchiveFile.string(
        'trips.txt',
        'route_id,service_id,trip_id,trip_headsign,direction_id\n'
            'route-1,weekday,trip-1,City Centre,0\n'
            'route-1,weekday,trip-without-stop-times,,1\n',
      ),
    );
  if (includeStopTimes) {
    archive.addFile(
      ArchiveFile.string(
        'stop_times.txt',
        'trip_id,arrival_time,departure_time,stop_id,stop_sequence\n'
            'trip-1,25:10:00,25:12:00,stop-1,1\n',
      ),
    );
  }
  return ZipEncoder().encode(archive);
}
