import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/services/analytics_service.dart';

void main() {
  test('HTTP 429 reports temporary rate limiting without retrying', () async {
    var requestCount = 0;
    final service = GtfsRealtimeService(
      client: MockClient((request) async {
        requestCount += 1;
        return http.Response('', 429);
      }),
    );

    await expectLater(
      service.fetchVehiclePositions(),
      throwsA(
        isA<GtfsRealtimeException>().having(
          (error) => error.message,
          'message',
          contains('too many requests'),
        ),
      ),
    );
    expect(requestCount, 1);
    service.close();
  });

  test('decodes usable vehicle routes', () async {
    final feed = gtfs.FeedMessage(
      header: gtfs.FeedHeader(gtfsRealtimeVersion: '2.0'),
      entity: [
        gtfs.FeedEntity(
          id: 'vehicle-1',
          vehicle: gtfs.VehiclePosition(
            trip: gtfs.TripDescriptor(routeId: 'route-1'),
            position: gtfs.Position(latitude: 3, longitude: 101),
            congestionLevel:
                gtfs.VehiclePosition_CongestionLevel.SEVERE_CONGESTION,
          ),
        ),
        gtfs.FeedEntity(
          id: 'missing-position',
          vehicle: gtfs.VehiclePosition(
            trip: gtfs.TripDescriptor(routeId: 'route-2'),
          ),
        ),
      ],
    );
    final service = GtfsRealtimeService(
      client: MockClient(
        (request) async => http.Response.bytes(feed.writeToBuffer(), 200),
      ),
    );

    final result = await service.fetchVehiclePositions();

    expect(result.totalEntities, 2);
    expect(result.vehicles, hasLength(1));
    expect(result.vehicles.single.routeId, 'route-1');
    expect(result.vehicles.single.timestamp, isNull);
    expect(
      result.vehicles.single.congestionLevel,
      TransitCongestionLevel.severe,
    );
    service.close();
  });
}
