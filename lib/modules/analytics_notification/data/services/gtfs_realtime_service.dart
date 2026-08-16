import 'dart:async';

import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;
import 'package:http/http.dart' as http;
import 'package:nextroute_assignment/modules/analytics_notification/data/models/realtime_vehicle.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/vehicle_position_feed.dart';

class GtfsRealtimeService {
  GtfsRealtimeService({
    http.Client? client,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  static final Uri endpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl',
  );

  final http.Client _client;
  final bool _ownsClient;
  final Duration requestTimeout;

  Future<VehiclePositionFeed> fetchVehiclePositions() async {
    try {
      final response = await _client.get(endpoint).timeout(requestTimeout);

      if (response.statusCode == 429) {
        throw const GtfsRealtimeException(
          'Realtime data is temporarily unavailable because the data service '
          'is receiving too many requests. Please wait a moment and try again.',
        );
      }

      if (response.statusCode != 200) {
        throw GtfsRealtimeException(
          'Government realtime feed returned HTTP ${response.statusCode}.',
        );
      }

      if (response.bodyBytes.isEmpty) {
        throw const GtfsRealtimeException(
          'Government realtime feed returned an empty response.',
        );
      }

      final feedMessage = gtfs.FeedMessage.fromBuffer(response.bodyBytes);
      if (!feedMessage.isInitialized()) {
        throw const GtfsRealtimeException(
          'Government realtime feed contained incomplete protobuf data.',
        );
      }

      final vehicles = <RealtimeVehicle>[];

      for (final entity in feedMessage.entity) {
        if (!entity.hasVehicle()) {
          continue;
        }

        final vehiclePosition = entity.vehicle;
        if (!vehiclePosition.hasPosition()) {
          continue;
        }

        final position = vehiclePosition.position;
        if (!position.hasLatitude() || !position.hasLongitude()) {
          continue;
        }

        final latitude = position.latitude;
        final longitude = position.longitude;
        if (!latitude.isFinite ||
            !longitude.isFinite ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          continue;
        }

        final trip = vehiclePosition.hasTrip() ? vehiclePosition.trip : null;
        final vehicle = vehiclePosition.hasVehicle()
            ? vehiclePosition.vehicle
            : null;

        vehicles.add(
          RealtimeVehicle(
            vehicleId: vehicle == null
                ? null
                : _optionalString(vehicle.hasId(), vehicle.id),
            tripId: trip == null
                ? null
                : _optionalString(trip.hasTripId(), trip.tripId),
            routeId: trip == null
                ? null
                : _optionalString(trip.hasRouteId(), trip.routeId),
            latitude: latitude,
            longitude: longitude,
            timestamp: _decodeTimestamp(vehiclePosition),
            currentStopSequence: vehiclePosition.hasCurrentStopSequence()
                ? vehiclePosition.currentStopSequence
                : null,
            stopId: _optionalString(
              vehiclePosition.hasStopId(),
              vehiclePosition.stopId,
            ),
            currentStatus: _decodeCurrentStatus(vehiclePosition),
          ),
        );
      }

      return VehiclePositionFeed(
        totalEntities: feedMessage.entity.length,
        vehicles: List.unmodifiable(vehicles),
      );
    } on TimeoutException {
      throw GtfsRealtimeException(
        'Government realtime feed did not respond within '
        '${requestTimeout.inSeconds} seconds.',
      );
    } on http.ClientException catch (error) {
      throw GtfsRealtimeException(
        'Could not connect to the government realtime feed.',
        cause: error,
      );
    } on GtfsRealtimeException {
      rethrow;
    } catch (error) {
      throw GtfsRealtimeException(
        'Could not process the GTFS-Realtime response.',
        cause: error,
      );
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  static String? _optionalString(bool isPresent, String value) {
    if (!isPresent) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static DateTime? _decodeTimestamp(gtfs.VehiclePosition vehiclePosition) {
    if (!vehiclePosition.hasTimestamp()) {
      return null;
    }

    try {
      return DateTime.fromMillisecondsSinceEpoch(
        vehiclePosition.timestamp.toInt() * 1000,
        isUtc: true,
      );
    } on ArgumentError {
      return null;
    }
  }

  static RealtimeVehicleStopStatus? _decodeCurrentStatus(
    gtfs.VehiclePosition vehiclePosition,
  ) {
    if (!vehiclePosition.hasCurrentStatus()) {
      return null;
    }

    final status = vehiclePosition.currentStatus;
    if (status == gtfs.VehiclePosition_VehicleStopStatus.INCOMING_AT) {
      return RealtimeVehicleStopStatus.incomingAt;
    }
    if (status == gtfs.VehiclePosition_VehicleStopStatus.STOPPED_AT) {
      return RealtimeVehicleStopStatus.stoppedAt;
    }
    if (status == gtfs.VehiclePosition_VehicleStopStatus.IN_TRANSIT_TO) {
      return RealtimeVehicleStopStatus.inTransitTo;
    }
    return null;
  }
}

class GtfsRealtimeException implements Exception {
  const GtfsRealtimeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}
