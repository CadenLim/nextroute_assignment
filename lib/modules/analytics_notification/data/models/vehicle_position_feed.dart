import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';

class VehiclePositionFeed {
  const VehiclePositionFeed({
    required this.totalEntities,
    required this.vehicles,
  });

  final int totalEntities;
  final List<RealtimeVehicle> vehicles;

  int get usableVehiclePositions => vehicles.length;
}
