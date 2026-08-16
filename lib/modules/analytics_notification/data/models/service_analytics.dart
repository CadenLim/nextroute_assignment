class ServiceAnalytics {
  const ServiceAnalytics({
    required this.vehicleCount,
    required this.routeCount,
    required this.vehiclesByRoute,
    required this.latestUpdate,
  });

  final int vehicleCount;
  final int routeCount;
  final Map<String, int> vehiclesByRoute;
  final DateTime? latestUpdate;
}
