class GtfsStopTime {
  const GtfsStopTime({
    required this.tripId,
    required this.arrivalTime,
    required this.departureTime,
    required this.stopId,
    required this.stopSequence,
  });

  final String tripId;
  final String arrivalTime;
  final String departureTime;
  final String stopId;
  final int stopSequence;
}
