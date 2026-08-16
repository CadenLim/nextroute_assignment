import 'package:nextroute_assignment/modules/analytics_notification/data/models/service_analytics.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';

class ServiceAnalyticsCalculator {
  const ServiceAnalyticsCalculator();

  ServiceAnalytics calculate(VehiclePositionFeed feed) {
    final routeCounts = <String, int>{};
    DateTime? latestUpdate;

    for (final vehicle in feed.vehicles) {
      final routeId = vehicle.routeId;
      if (routeId != null && routeId.isNotEmpty) {
        routeCounts.update(routeId, (count) => count + 1, ifAbsent: () => 1);
      }

      final timestamp = vehicle.timestamp;
      if (timestamp != null &&
          (latestUpdate == null || timestamp.isAfter(latestUpdate))) {
        latestUpdate = timestamp;
      }
    }

    final sortedRoutes = routeCounts.entries.toList()
      ..sort((first, second) {
        final countComparison = second.value.compareTo(first.value);
        if (countComparison != 0) {
          return countComparison;
        }
        return first.key.compareTo(second.key);
      });

    final vehiclesByRoute = <String, int>{
      for (final route in sortedRoutes) route.key: route.value,
    };

    return ServiceAnalytics(
      vehicleCount: feed.vehicles.length,
      routeCount: vehiclesByRoute.length,
      vehiclesByRoute: Map.unmodifiable(vehiclesByRoute),
      latestUpdate: latestUpdate,
    );
  }
}
