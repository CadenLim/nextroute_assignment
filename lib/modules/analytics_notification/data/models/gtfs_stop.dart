class GtfsStop {
  const GtfsStop({
    required this.stopId,
    required this.stopName,
    required this.stopLatitude,
    required this.stopLongitude,
  });

  final String stopId;
  final String? stopName;
  final double stopLatitude;
  final double stopLongitude;
}
