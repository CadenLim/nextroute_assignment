import 'package:flutter_test/flutter_test.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';
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

  test('protobuf decoding preserves explicit stop context fields', () async {
    final protobufFeed = gtfs.FeedMessage(
      header: gtfs.FeedHeader(gtfsRealtimeVersion: '2.0'),
      entity: [
        gtfs.FeedEntity(
          id: 'incoming',
          vehicle: gtfs.VehiclePosition(
            position: gtfs.Position(latitude: 3, longitude: 101),
            currentStopSequence: 1,
            stopId: 'stop-1',
            currentStatus: gtfs.VehiclePosition_VehicleStopStatus.INCOMING_AT,
          ),
        ),
        gtfs.FeedEntity(
          id: 'stopped',
          vehicle: gtfs.VehiclePosition(
            position: gtfs.Position(latitude: 3.1, longitude: 101.1),
            currentStopSequence: 2,
            stopId: 'stop-2',
            currentStatus: gtfs.VehiclePosition_VehicleStopStatus.STOPPED_AT,
          ),
        ),
        gtfs.FeedEntity(
          id: 'in-transit',
          vehicle: gtfs.VehiclePosition(
            position: gtfs.Position(latitude: 3.2, longitude: 101.2),
            currentStopSequence: 3,
            stopId: 'stop-3',
            currentStatus: gtfs.VehiclePosition_VehicleStopStatus.IN_TRANSIT_TO,
          ),
        ),
        gtfs.FeedEntity(
          id: 'implicit-status',
          vehicle: gtfs.VehiclePosition(
            position: gtfs.Position(latitude: 3.3, longitude: 101.3),
            currentStopSequence: 4,
            stopId: '   ',
          ),
        ),
      ],
    );
    final service = GtfsRealtimeService(
      client: MockClient(
        (request) async =>
            http.Response.bytes(protobufFeed.writeToBuffer(), 200),
      ),
    );

    final vehicles = (await service.fetchVehiclePositions()).vehicles;

    expect(vehicles.map((vehicle) => vehicle.currentStopSequence), [
      1,
      2,
      3,
      4,
    ]);
    expect(vehicles.first.stopId, 'stop-1');
    expect(vehicles.last.stopId, isNull);
    expect(vehicles.map((vehicle) => vehicle.currentStatus), [
      RealtimeVehicleStopStatus.incomingAt,
      RealtimeVehicleStopStatus.stoppedAt,
      RealtimeVehicleStopStatus.inTransitTo,
      null,
    ]);
    expect(
      vehicles.last.effectiveCurrentStatus,
      RealtimeVehicleStopStatus.inTransitTo,
    );
    service.close();
  });

  test('protobuf decoding preserves optional trip-instance metadata', () async {
    final protobufFeed = gtfs.FeedMessage(
      header: gtfs.FeedHeader(gtfsRealtimeVersion: '2.0'),
      entity: [
        gtfs.FeedEntity(
          id: 'with-instance-metadata',
          vehicle: gtfs.VehiclePosition(
            trip: gtfs.TripDescriptor(
              tripId: 'frequency-trip',
              startTime: '25:10:00',
              startDate: '20260817',
              scheduleRelationship:
                  gtfs.TripDescriptor_ScheduleRelationship.UNSCHEDULED,
            ),
            position: gtfs.Position(latitude: 3, longitude: 101),
          ),
        ),
        gtfs.FeedEntity(
          id: 'blank-instance-metadata',
          vehicle: gtfs.VehiclePosition(
            trip: gtfs.TripDescriptor(startTime: '   ', startDate: ''),
            position: gtfs.Position(latitude: 3.1, longitude: 101.1),
          ),
        ),
        gtfs.FeedEntity(
          id: 'without-instance-metadata',
          vehicle: gtfs.VehiclePosition(
            trip: gtfs.TripDescriptor(),
            position: gtfs.Position(latitude: 3.2, longitude: 101.2),
          ),
        ),
      ],
    );
    final service = GtfsRealtimeService(
      client: MockClient(
        (request) async =>
            http.Response.bytes(protobufFeed.writeToBuffer(), 200),
      ),
    );

    final vehicles = (await service.fetchVehiclePositions()).vehicles;

    expect(vehicles.first.tripStartTime, '25:10:00');
    expect(vehicles.first.tripStartDate, '20260817');
    expect(
      vehicles.first.scheduleRelationship,
      RealtimeTripScheduleRelationship.unscheduled,
    );
    expect(vehicles[1].tripStartTime, isNull);
    expect(vehicles[1].tripStartDate, isNull);
    expect(vehicles[1].scheduleRelationship, isNull);
    expect(vehicles.last.tripStartTime, isNull);
    expect(vehicles.last.tripStartDate, isNull);
    expect(vehicles.last.scheduleRelationship, isNull);
    service.close();
  });
}
