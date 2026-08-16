import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/service_analytics_calculator.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';

void main() {
  const calculator = ServiceAnalyticsCalculator();

  test('calculates vehicle and route counts with deterministic grouping', () {
    final feed = VehiclePositionFeed(
      totalEntities: 7,
      vehicles: [
        _vehicle(routeId: 'B'),
        _vehicle(routeId: 'A'),
        _vehicle(routeId: 'B'),
        _vehicle(routeId: 'C'),
        _vehicle(routeId: 'A'),
        _vehicle(routeId: null),
        _vehicle(routeId: ''),
      ],
    );

    final analytics = calculator.calculate(feed);

    expect(analytics.vehicleCount, 7);
    expect(analytics.routeCount, 3);
    expect(analytics.vehiclesByRoute, {'A': 2, 'B': 2, 'C': 1});
    expect(analytics.vehiclesByRoute.keys, orderedEquals(['A', 'B', 'C']));
  });

  test('selects the latest non-null vehicle timestamp', () {
    final first = DateTime.utc(2026, 8, 16, 8, 10);
    final latest = DateTime.utc(2026, 8, 16, 8, 15);
    final feed = VehiclePositionFeed(
      totalEntities: 3,
      vehicles: [
        _vehicle(timestamp: first),
        _vehicle(timestamp: null),
        _vehicle(timestamp: latest),
      ],
    );

    final analytics = calculator.calculate(feed);

    expect(analytics.latestUpdate, latest);
  });

  test('returns null latest update when all timestamps are missing', () {
    final feed = VehiclePositionFeed(
      totalEntities: 2,
      vehicles: [_vehicle(), _vehicle()],
    );

    final analytics = calculator.calculate(feed);

    expect(analytics.latestUpdate, isNull);
  });

  test('handles an empty feed', () {
    const feed = VehiclePositionFeed(totalEntities: 0, vehicles: []);

    final analytics = calculator.calculate(feed);

    expect(analytics.vehicleCount, 0);
    expect(analytics.routeCount, 0);
    expect(analytics.vehiclesByRoute, isEmpty);
    expect(analytics.latestUpdate, isNull);
  });
}

RealtimeVehicle _vehicle({String? routeId, DateTime? timestamp}) {
  return RealtimeVehicle(
    vehicleId: null,
    tripId: null,
    routeId: routeId,
    latitude: 3,
    longitude: 101,
    timestamp: timestamp,
  );
}
