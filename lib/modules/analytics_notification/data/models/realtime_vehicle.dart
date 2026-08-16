class RealtimeVehicle {
  const RealtimeVehicle({
    required this.vehicleId,
    required this.tripId,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  final String? vehicleId;
  final String? tripId;
  final String? routeId;
  final double latitude;
  final double longitude;
  final DateTime? timestamp;
}
