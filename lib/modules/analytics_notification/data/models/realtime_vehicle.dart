enum RealtimeVehicleStopStatus { incomingAt, stoppedAt, inTransitTo }

enum RealtimeTripScheduleRelationship {
  scheduled,
  added,
  unscheduled,
  canceled,
  replacement,
  duplicated,
  deleted,
}

class RealtimeVehicle {
  const RealtimeVehicle({
    required this.vehicleId,
    required this.tripId,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.currentStopSequence,
    this.stopId,
    this.currentStatus,
    this.tripStartTime,
    this.tripStartDate,
    this.scheduleRelationship,
  });

  final String? vehicleId;
  final String? tripId;
  final String? routeId;
  final double latitude;
  final double longitude;
  final DateTime? timestamp;
  final int? currentStopSequence;
  final String? stopId;
  final RealtimeVehicleStopStatus? currentStatus;
  final String? tripStartTime;
  final String? tripStartDate;
  final RealtimeTripScheduleRelationship? scheduleRelationship;

  RealtimeVehicleStopStatus? get effectiveCurrentStatus {
    if (currentStatus != null) {
      return currentStatus;
    }
    if (currentStopSequence != null) {
      return RealtimeVehicleStopStatus.inTransitTo;
    }
    return null;
  }
}
