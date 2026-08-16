class GtfsRoute {
  const GtfsRoute({
    required this.routeId,
    required this.routeShortName,
    required this.routeLongName,
    required this.routeType,
  });

  final String routeId;
  final String? routeShortName;
  final String? routeLongName;
  final int routeType;
}
