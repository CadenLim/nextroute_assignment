import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/services/gtfs_realtime_service.dart';

void main() {
  test('HTTP 429 reports temporary rate limiting without retrying', () async {
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount += 1;
      return http.Response('', 429);
    });
    final service = GtfsRealtimeService(client: client);

    await expectLater(
      service.fetchVehiclePositions(),
      throwsA(
        isA<GtfsRealtimeException>().having(
          (error) => error.message.toLowerCase(),
          'message',
          allOf(
            contains('temporarily'),
            contains('too many requests'),
            contains('try again'),
          ),
        ),
      ),
    );
    expect(requestCount, 1);
    service.close();
  });

  test(
    'protobuf decoding preserves a usable VehiclePosition trip ID',
    () async {
      final protobufFeed = gtfs.FeedMessage(
        header: gtfs.FeedHeader(gtfsRealtimeVersion: '2.0'),
        entity: [
          gtfs.FeedEntity(
            id: 'entity-with-trip',
            vehicle: gtfs.VehiclePosition(
              trip: gtfs.TripDescriptor(tripId: 'trip-123', routeId: 'route-1'),
              position: gtfs.Position(latitude: 3, longitude: 101),
            ),
          ),
          gtfs.FeedEntity(
            id: 'entity-with-blank-trip',
            vehicle: gtfs.VehiclePosition(
              trip: gtfs.TripDescriptor(tripId: '   ', routeId: 'route-1'),
              position: gtfs.Position(latitude: 3.1, longitude: 101.1),
            ),
          ),
        ],
      );
      final client = MockClient(
        (request) async =>
            http.Response.bytes(protobufFeed.writeToBuffer(), 200),
      );
      final service = GtfsRealtimeService(client: client);

      final feed = await service.fetchVehiclePositions();

      expect(feed.vehicles, hasLength(2));
      expect(feed.vehicles.first.tripId, 'trip-123');
      expect(feed.vehicles.last.tripId, isNull);
      service.close();
    },
  );
}
