import 'dart:async';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;
import 'package:http/http.dart' as http;
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
          'is receiving too many requests. Please wait and try again.',
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
        if (!entity.hasVehicle() || !entity.vehicle.hasPosition()) {
          continue;
        }

        final vehicle = entity.vehicle;
        final position = vehicle.position;
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

        vehicles.add(
          RealtimeVehicle(
            routeId: vehicle.hasTrip()
                ? _optionalString(
                    vehicle.trip.hasRouteId(),
                    vehicle.trip.routeId,
                  )
                : null,
            timestamp: _decodeTimestamp(vehicle),
            congestionLevel: _decodeCongestionLevel(vehicle),
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

  static DateTime? _decodeTimestamp(gtfs.VehiclePosition vehicle) {
    if (!vehicle.hasTimestamp()) {
      return null;
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        vehicle.timestamp.toInt() * 1000,
        isUtc: true,
      );
    } on ArgumentError {
      return null;
    }
  }

  static TransitCongestionLevel _decodeCongestionLevel(
    gtfs.VehiclePosition vehicle,
  ) {
    if (!vehicle.hasCongestionLevel()) {
      return TransitCongestionLevel.unknown;
    }
    return switch (vehicle.congestionLevel.value) {
      1 => TransitCongestionLevel.smooth,
      2 => TransitCongestionLevel.stopAndGo,
      3 => TransitCongestionLevel.congested,
      4 => TransitCongestionLevel.severe,
      _ => TransitCongestionLevel.unknown,
    };
  }
}

class GtfsRealtimeException implements Exception {
  const GtfsRealtimeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class ServiceAnalyticsCalculator {
  const ServiceAnalyticsCalculator();

  ServiceAnalytics calculate(VehiclePositionFeed feed) {
    final routeCounts = <String, int>{};
    DateTime? latestUpdate;
    var congestedVehicleCount = 0;
    var severeCongestionCount = 0;

    for (final vehicle in feed.vehicles) {
      final routeId = vehicle.routeId;
      if (routeId != null && routeId.isNotEmpty) {
        routeCounts.update(routeId, (count) => count + 1, ifAbsent: () => 1);
      }
      if (vehicle.congestionLevel == TransitCongestionLevel.congested) {
        congestedVehicleCount += 1;
      } else if (vehicle.congestionLevel == TransitCongestionLevel.severe) {
        congestedVehicleCount += 1;
        severeCongestionCount += 1;
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
        return countComparison != 0
            ? countComparison
            : first.key.compareTo(second.key);
      });

    final vehiclesByRoute = <String, int>{
      for (final route in sortedRoutes) route.key: route.value,
    };
    return ServiceAnalytics(
      vehicleCount: feed.vehicles.length,
      routeCount: vehiclesByRoute.length,
      vehiclesByRoute: Map.unmodifiable(vehiclesByRoute),
      latestUpdate: latestUpdate,
      congestedVehicleCount: congestedVehicleCount,
      severeCongestionCount: severeCongestionCount,
    );
  }
}

class SupabaseAnalyticsRepository {
  SupabaseAnalyticsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<DailyAnalyticsSummary>> loadLastSevenDays({DateTime? now}) async {
    final today = (now ?? DateTime.now()).toLocal();
    final firstDay = DateTime(
      today.year,
      today.month,
      today.day,
    ).subtract(const Duration(days: 6));
    final lastDay = DateTime(today.year, today.month, today.day);
    final rows = await _client
        .from('analytics_daily_summary')
        .select()
        .gte('service_date', _dateOnly(firstDay))
        .lte('service_date', _dateOnly(lastDay))
        .order('service_date');

    return List.unmodifiable(rows.map(DailyAnalyticsSummary.fromSupabase));
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

class BusRouteInfo {
  const BusRouteInfo({
    required this.id,
    required this.shortName,
    required this.longName,
  });

  final String id;
  final String shortName;
  final String longName;

  String get displayName => shortName.isEmpty ? id : 'Route $shortName';
}

class BusRouteCatalog {
  const BusRouteCatalog._();

  static Future<Map<String, BusRouteInfo>> load() async {
    final raw = await rootBundle.loadString('assets/gtfs/bus/routes.txt');
    final rows = const CsvToListConverter(eol: '\n').convert(raw);
    if (rows.isEmpty) return const {};
    final headers = rows.first.map((value) => '$value'.trim()).toList();
    final idIndex = headers.indexOf('route_id');
    final shortNameIndex = headers.indexOf('route_short_name');
    final longNameIndex = headers.indexOf('route_long_name');
    if (idIndex < 0 || shortNameIndex < 0 || longNameIndex < 0) {
      throw const FormatException(
        'Bus routes file is missing required fields.',
      );
    }

    final routes = <String, BusRouteInfo>{};
    for (final row in rows.skip(1)) {
      if (row.length <= longNameIndex) continue;
      final id = '${row[idIndex]}'.trim();
      if (id.isEmpty) continue;
      routes[id] = BusRouteInfo(
        id: id,
        shortName: '${row[shortNameIndex]}'.trim(),
        longName: '${row[longNameIndex]}'.trim(),
      );
    }
    return Map.unmodifiable(routes);
  }
}
