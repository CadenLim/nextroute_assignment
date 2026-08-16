class GtfsTrip {
  const GtfsTrip({
    required this.routeId,
    required this.serviceId,
    required this.tripId,
    required this.tripHeadsign,
    required this.directionId,
  });

  final String routeId;
  final String serviceId;
  final String tripId;
  final String? tripHeadsign;
  final int? directionId;
}
