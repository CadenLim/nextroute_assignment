import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map/flutter_map.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart'
    hide Position;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:location/location.dart' as loc;
import 'package:permission_handler/permission_handler.dart' as handler;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _blue = Color(0xFF2563EB);
const _navy = Color(0xFF27364C);
const _page = Color(0xFFF1F5F9);
const _ink = Color(0xFF1E293B);

class Station {
  final String name;
  final double distance;
  final List<String> lines;
  final double latitude;
  final double longitude;
  final String type;
  final bool? accessible;
  final List<String> stopIds;
  final List<String> sources;
  final String? landmark;

  const Station(
      this.name,
      this.distance,
      this.lines, {
        this.latitude = 0,
        this.longitude = 0,
        this.type = 'Rail',
        this.accessible,
        this.stopIds = const [],
        this.sources = const [],
        this.landmark,
      });

  Station withDistance(double value) => Station(
    name,
    value,
    lines,
    latitude: latitude,
    longitude: longitude,
    type: type,
    accessible: accessible,
    stopIds: stopIds,
    sources: sources,
    landmark: landmark,
  );

  bool get hasDistance => distance.isFinite;
}

class LiveVehicle {
  final String id;
  final String routeId;
  final double latitude;
  final double longitude;
  final DateTime? updatedAt;

  const LiveVehicle({
    required this.id,
    required this.routeId,
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });
}

class TransitRoute {
  final String id;
  final String shortName;
  final String longName;
  final Set<String> stopIds;

  const TransitRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.stopIds,
  });

  String get displayName {
    if (shortName.trim().isNotEmpty) return shortName.trim();
    final fallback = longName.trim();
    if (RegExp(r'^[A-Za-z]*\d+[A-Za-z]?$').hasMatch(fallback)) {
      return fallback;
    }
    return id;
  }

  String get description {
    final value = longName.trim();
    return value == displayName ? '' : value;
  }
}

class TransitRouteRepository {
  static final Map<String, List<TransitRoute>> _cache = {};

  static Future<List<TransitRoute>> load(String base) async {
    final cached = _cache[base];
    if (cached != null) return cached;

    final routeRows = (await rootBundle.loadString(
      '$base/routes.txt',
    )).split(RegExp(r'\r?\n'));
    final tripRows = (await rootBundle.loadString(
      '$base/trips.txt',
    )).split(RegExp(r'\r?\n'));
    final stopTimeRows = (await rootBundle.loadString(
      '$base/stop_times.txt',
    )).split(RegExp(r'\r?\n'));

    final routeDetails = <String, (String, String)>{};
    if (routeRows.isNotEmpty) {
      final header = _csvRow(routeRows.first);
      final idIndex = header.indexOf('route_id');
      final shortIndex = header.indexOf('route_short_name');
      final longIndex = header.indexOf('route_long_name');
      for (final row in routeRows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (idIndex < 0 || values.length <= idIndex) continue;
        final id = values[idIndex].trim();
        final shortName = shortIndex >= 0 && values.length > shortIndex
            ? values[shortIndex].trim()
            : id;
        final longName = longIndex >= 0 && values.length > longIndex
            ? values[longIndex].trim()
            : '';
        routeDetails[id] = (shortName, longName);
      }
    }

    final routeByTrip = <String, String>{};
    if (tripRows.isNotEmpty) {
      final header = _csvRow(tripRows.first);
      final tripIndex = header.indexOf('trip_id');
      final routeIndex = header.indexOf('route_id');
      final required = math.max(tripIndex, routeIndex);
      for (final row in tripRows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (required < 0 || values.length <= required) continue;
        routeByTrip[values[tripIndex].trim()] = values[routeIndex].trim();
      }
    }

    final stopsByRoute = <String, Set<String>>{};
    if (stopTimeRows.isNotEmpty) {
      final header = _csvRow(stopTimeRows.first);
      final tripIndex = header.indexOf('trip_id');
      final stopIndex = header.indexOf('stop_id');
      final required = math.max(tripIndex, stopIndex);
      for (final row in stopTimeRows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (required < 0 || values.length <= required) continue;
        final routeId = routeByTrip[values[tripIndex].trim()];
        if (routeId == null) continue;
        stopsByRoute
            .putIfAbsent(routeId, () => {})
            .add(values[stopIndex].trim());
      }
    }

    final routes =
    routeDetails.entries
        .where((entry) => stopsByRoute[entry.key]?.isNotEmpty == true)
        .map(
          (entry) => TransitRoute(
        id: entry.key,
        shortName: entry.value.$1,
        longName: entry.value.$2,
        stopIds: stopsByRoute[entry.key]!,
      ),
    )
        .toList()
      ..sort((a, b) => _compareRouteNames(a.displayName, b.displayName));
    _cache[base] = routes;
    return routes;
  }

  static int _compareRouteNames(String left, String right) {
    final leftNumber = int.tryParse(
      RegExp(r'\d+').firstMatch(left)?.group(0) ?? '',
    );
    final rightNumber = int.tryParse(
      RegExp(r'\d+').firstMatch(right)?.group(0) ?? '',
    );
    if (leftNumber != null &&
        rightNumber != null &&
        leftNumber != rightNumber) {
      return leftNumber.compareTo(rightNumber);
    }
    return left.toUpperCase().compareTo(right.toUpperCase());
  }
}

class RailShape {
  final String routeId;
  final Color color;
  final List<LatLng> points;

  const RailShape({
    required this.routeId,
    required this.color,
    required this.points,
  });
}

class RailShapeRepository {
  static List<RailShape>? _cache;

  static Future<List<RailShape>> load() async {
    if (_cache != null) return _cache!;
    const base = 'assets/gtfs/rail';

    final routeRows = (await rootBundle.loadString(
      '$base/routes.txt',
    )).split(RegExp(r'\r?\n'));
    final tripRows = (await rootBundle.loadString(
      '$base/trips.txt',
    )).split(RegExp(r'\r?\n'));

    final colorsByRoute = <String, Color>{};
    if (routeRows.isNotEmpty) {
      final header = _csvRow(routeRows.first);
      final idIndex = header.indexOf('route_id');
      final colorIndex = header.indexOf('route_color');
      final required = math.max(idIndex, colorIndex);
      for (final row in routeRows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (required < 0 || values.length <= required) continue;
        colorsByRoute[values[idIndex].trim()] = _parseGtfsColor(
          values[colorIndex].trim(),
        );
      }
    }

    final routeByShape = <String, String>{};
    final preferredShapeByRoute = <String, String>{};
    if (tripRows.isNotEmpty) {
      final header = _csvRow(tripRows.first);
      final routeIndex = header.indexOf('route_id');
      final shapeIndex = header.indexOf('shape_id');
      final directionIndex = header.indexOf('direction_id');
      final required = math.max(routeIndex, shapeIndex);
      for (final row in tripRows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (required < 0 || values.length <= required) continue;
        final routeId = values[routeIndex].trim();
        final shapeId = values[shapeIndex].trim();
        if (routeId.isEmpty || shapeId.isEmpty) continue;
        routeByShape[shapeId] = routeId;
        final isFirstDirection =
            directionIndex < 0 ||
                values.length <= directionIndex ||
                values[directionIndex].trim() == '0';
        if (isFirstDirection) {
          preferredShapeByRoute.putIfAbsent(routeId, () => shapeId);
        }
      }
    }

    final preferredShapeIds = preferredShapeByRoute.values.toSet();
    final pointsByShape = <String, List<(int, LatLng)>>{};
    final shapeRows = (await rootBundle.loadString(
      '$base/shapes.txt',
    )).split(RegExp(r'\r?\n'));
    if (shapeRows.isNotEmpty) {
      final header = _csvRow(shapeRows.first);
      final idIndex = header.indexOf('shape_id');
      final latitudeIndex = header.indexOf('shape_pt_lat');
      final longitudeIndex = header.indexOf('shape_pt_lon');
      final sequenceIndex = header.indexOf('shape_pt_sequence');
      final required = [
        idIndex,
        latitudeIndex,
        longitudeIndex,
        sequenceIndex,
      ].reduce(math.max);
      for (final row in shapeRows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (required < 0 || values.length <= required) continue;
        final shapeId = values[idIndex].trim();
        if (!preferredShapeIds.contains(shapeId)) continue;
        final latitude = double.tryParse(values[latitudeIndex].trim());
        final longitude = double.tryParse(values[longitudeIndex].trim());
        final sequence = int.tryParse(values[sequenceIndex].trim());
        if (latitude == null || longitude == null || sequence == null) continue;
        pointsByShape.putIfAbsent(shapeId, () => []).add((
        sequence,
        LatLng(latitude, longitude),
        ));
      }
    }

    final result = <RailShape>[];
    for (final entry in pointsByShape.entries) {
      final routeId = routeByShape[entry.key];
      if (routeId == null) continue;
      entry.value.sort((a, b) => a.$1.compareTo(b.$1));
      result.add(
        RailShape(
          routeId: routeId,
          color: colorsByRoute[routeId] ?? _blue,
          points: entry.value.map((point) => point.$2).toList(),
        ),
      );
    }
    _cache = result;
    return result;
  }

  static Color _parseGtfsColor(String value) {
    final cleaned = value.replaceFirst('#', '').trim();
    final parsed = int.tryParse(cleaned, radix: 16);
    return parsed == null ? _blue : Color(0xFF000000 | parsed);
  }
}

class DeviceLocationService {
  static final loc.Location location = loc.Location();

  static Future<bool> isPermissionGranted() async {
    final status = await location.hasPermission();
    return status == loc.PermissionStatus.granted;
  }

  static Future<bool> isGpsEnabled() async {
    return location.serviceEnabled();
  }

  static Future<void> prepare() async {
    if (!kIsWeb && !await isGpsEnabled()) {
      final enabled = await location.requestService();
      if (!enabled) {
        throw Exception('Location services are disabled on this device.');
      }
    }

    if (!await isPermissionGranted()) {
      final permission = await location.requestPermission();
      if (permission == loc.PermissionStatus.deniedForever) {
        throw Exception(
          'Location permission is permanently denied. Enable it in app settings.',
        );
      }
      if (permission != loc.PermissionStatus.granted) {
        throw Exception('Location permission was denied.');
      }
    }
  }

  static Future<loc.LocationData> currentLocation() async {
    await prepare();
    await location.changeSettings(
      accuracy: loc.LocationAccuracy.high,
      interval: 5000,
      distanceFilter: 10,
    );
    return location.getLocation();
  }

  static Stream<loc.LocationData> locationStream() {
    return location.onLocationChanged;
  }

  static Future<void> openSettings() async {
    if (kIsWeb) {
      throw Exception(
        'Open the browser site settings and allow Location for localhost.',
      );
    }
    if (!await handler.openAppSettings()) {
      throw Exception('Could not open application settings.');
    }
  }
}

bool isInsideMalaysia(double latitude, double longitude) {
  return latitude >= 0.5 &&
      latitude <= 7.8 &&
      longitude >= 99.0 &&
      longitude <= 120.5;
}

String locationOutsideCoverageMessage(double latitude, double longitude) {
  if (!isInsideMalaysia(latitude, longitude)) {
    return 'Your device location is outside Malaysia '
        '(${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}). '
        'Android Emulator normally starts in Mountain View, USA. Open the '
        'emulator More menu (three dots), choose Location, search Kuala Lumpur, '
        'then press Set location.';
  }
  return 'No station in this dataset is close to your current location. '
      'This Module 2 dataset covers Klang Valley services only.';
}

double distanceKm(
    double latitude1,
    double longitude1,
    double latitude2,
    double longitude2,
    ) {
  const radius = 6371.0;
  double radians(double value) => value * math.pi / 180;
  final dLatitude = radians(latitude2 - latitude1);
  final dLongitude = radians(longitude2 - longitude1);
  final a =
      math.sin(dLatitude / 2) * math.sin(dLatitude / 2) +
          math.cos(radians(latitude1)) *
              math.cos(radians(latitude2)) *
              math.sin(dLongitude / 2) *
              math.sin(dLongitude / 2);
  return radius * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
}

List<String> _csvRow(String row) {
  final values = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var i = 0; i < row.length; i++) {
    final char = row[i];
    if (char == '"') {
      if (quoted && i + 1 < row.length && row[i + 1] == '"') {
        buffer.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (char == ',' && !quoted) {
      values.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  values.add(buffer.toString().trim());
  return values;
}

class RealtimeVehicleService {
  static Future<List<LiveVehicle>> loadPrasaranaVehicles(
      String category,
      ) async {
    final url = Uri.https(
      'api.data.gov.my',
      '/gtfs-realtime/vehicle-position/prasarana',
      {'category': category},
    );
    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Live API returned HTTP ${response.statusCode}.');
    }

    final feed = FeedMessage.fromBuffer(response.bodyBytes);
    final vehicles = <LiveVehicle>[];
    for (final entity in feed.entity) {
      if (!entity.hasVehicle() || !entity.vehicle.hasPosition()) continue;
      final vehicle = entity.vehicle;
      final latitude = vehicle.position.latitude.toDouble();
      final longitude = vehicle.position.longitude.toDouble();
      if (latitude == 0 || longitude == 0) continue;
      final timestamp = vehicle.timestamp.toInt();
      vehicles.add(
        LiveVehicle(
          id: vehicle.vehicle.id.isEmpty ? entity.id : vehicle.vehicle.id,
          routeId: vehicle.trip.routeId,
          latitude: latitude,
          longitude: longitude,
          updatedAt: timestamp == 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
        ),
      );
    }
    return vehicles;
  }
}

class DepartureGroup {
  final String route;
  final String destination;
  final List<String> times;
  final List<String> frequencyNotes;
  final int nextMinutes;

  const DepartureGroup({
    required this.route,
    required this.destination,
    required this.times,
    this.frequencyNotes = const [],
    required this.nextMinutes,
  });
}

class ScheduleResult {
  final List<DepartureGroup> groups;
  final List<String> notices;

  const ScheduleResult({required this.groups, required this.notices});
}

class _TripInfo {
  final String routeId;
  final String serviceId;
  final String headsign;

  const _TripInfo(this.routeId, this.serviceId, this.headsign);
}

class _RouteInfo {
  final String shortName;
  final String longName;

  const _RouteInfo(this.shortName, this.longName);
}

class _FrequencyInfo {
  final int startSeconds;
  final int endSeconds;
  final int headwaySeconds;
  final bool exactTimes;

  const _FrequencyInfo({
    required this.startSeconds,
    required this.endSeconds,
    required this.headwaySeconds,
    required this.exactTimes,
  });
}

class _DepartureAccumulator {
  final String route;
  final String destination;
  final Map<int, bool> departures = {};
  final Map<int, String> frequencyNotes = {};

  _DepartureAccumulator({required this.route, required this.destination});

  void addDeparture(int seconds, {required bool estimated}) {
    departures.update(
      seconds,
          (wasEstimated) => wasEstimated && estimated,
      ifAbsent: () => estimated,
    );
  }
}

class StaticScheduleService {
  static Future<ScheduleResult> loadDepartures(Station station) async {
    if (station.stopIds.isEmpty || station.sources.isEmpty) {
      return const ScheduleResult(groups: [], notices: []);
    }

    final now = DateTime.now();
    final groups = <String, _DepartureAccumulator>{};
    final notices = <String>[];
    final nowSeconds = now.hour * 3600 + now.minute * 60 + now.second;

    for (final source in station.sources) {
      final base = 'assets/gtfs/$source';
      final calendar = await _activeServices(base, now);
      if (calendar.$2 != null) notices.add(calendar.$2!);
      if (calendar.$1.isEmpty) continue;

      final trips = await _loadTrips(base);
      final routes = await _loadRoutes(base);
      final frequencies = await _loadFrequencies(base);
      final raw = await rootBundle.loadString('$base/stop_times.txt');
      final rows = raw.split(RegExp(r'\r?\n'));
      if (rows.isEmpty) continue;
      final header = _csvRow(rows.first);
      final tripIndex = header.indexOf('trip_id');
      final departureIndex = header.indexOf('departure_time');
      final stopIndex = header.indexOf('stop_id');
      if (tripIndex < 0 || departureIndex < 0 || stopIndex < 0) continue;
      final requiredLength = math.max(
        tripIndex,
        math.max(departureIndex, stopIndex),
      );

      final firstDepartureByTrip = <String, int>{};
      final stationStopTimes = <(String, int)>[];

      for (final row in rows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (values.length <= requiredLength) continue;
        final tripId = values[tripIndex].trim();
        final departureSeconds = _timeSeconds(values[departureIndex].trim());
        if (departureSeconds < 0) continue;
        firstDepartureByTrip.update(
          tripId,
              (current) => math.min(current, departureSeconds),
          ifAbsent: () => departureSeconds,
        );
        if (station.stopIds.contains(values[stopIndex].trim())) {
          stationStopTimes.add((tripId, departureSeconds));
        }
      }

      for (final stopTime in stationStopTimes) {
        final tripId = stopTime.$1;
        final scheduledSeconds = stopTime.$2;
        final trip = trips[tripId];
        if (trip == null || !calendar.$1.contains(trip.serviceId)) continue;
        final route = routes[trip.routeId];
        final routeLabel = route?.shortName.isNotEmpty == true
            ? route!.shortName
            : trip.routeId;
        final destination = trip.headsign.isNotEmpty
            ? _cleanHeadsign(trip.headsign)
            : (route?.longName.isNotEmpty == true
            ? route!.longName
            : 'Scheduled service');
        final key = '$source|$routeLabel|$destination';
        final group = groups.putIfAbsent(
          key,
              () => _DepartureAccumulator(
            route: routeLabel,
            destination: destination,
          ),
        );

        final tripFrequencies = frequencies[tripId];
        if (tripFrequencies == null || tripFrequencies.isEmpty) {
          if (scheduledSeconds >= nowSeconds) {
            group.addDeparture(scheduledSeconds, estimated: false);
          }
          continue;
        }

        final firstDeparture = firstDepartureByTrip[tripId];
        if (firstDeparture == null) continue;
        final stopOffset = scheduledSeconds - firstDeparture;

        for (final frequency in tripFrequencies) {
          final stationStart = frequency.startSeconds + stopOffset;
          final stationEnd = frequency.endSeconds + stopOffset;
          if (stationEnd <= nowSeconds) continue;

          group.frequencyNotes[stationStart] = _frequencyDescription(
            frequency,
            stationStart,
            stationEnd,
          );

          for (
          var departure = stationStart;
          departure < stationEnd;
          departure += frequency.headwaySeconds
          ) {
            if (departure < nowSeconds) continue;
            group.addDeparture(departure, estimated: !frequency.exactTimes);
          }
        }
      }
    }

    final result =
    groups.values.where((group) => group.departures.isNotEmpty).map((
        group,
        ) {
      final departures = group.departures.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      final frequencyNotes = group.frequencyNotes.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));
      return DepartureGroup(
        route: group.route,
        destination: group.destination,
        times: departures.take(6).map((departure) {
          final prefix = departure.value ? 'Est. ' : '';
          return '$prefix${_displaySeconds(departure.key)}';
        }).toList(),
        frequencyNotes: frequencyNotes.map((entry) => entry.value).toList(),
        nextMinutes: departures.first.key,
      );
    }).toList()..sort((a, b) => a.nextMinutes.compareTo(b.nextMinutes));

    return ScheduleResult(groups: result.take(10).toList(), notices: notices);
  }

  static Future<Map<String, _TripInfo>> _loadTrips(String base) async {
    final rows = (await rootBundle.loadString(
      '$base/trips.txt',
    )).split(RegExp(r'\r?\n'));
    if (rows.isEmpty) return {};
    final header = _csvRow(rows.first);
    final routeIndex = header.indexOf('route_id');
    final serviceIndex = header.indexOf('service_id');
    final tripIndex = header.indexOf('trip_id');
    final headsignIndex = header.indexOf('trip_headsign');
    final result = <String, _TripInfo>{};
    for (final row in rows.skip(1)) {
      final values = _csvRow(row);
      if (values.length <= math.max(tripIndex, serviceIndex)) continue;
      result[values[tripIndex].trim()] = _TripInfo(
        values[routeIndex].trim(),
        values[serviceIndex].trim(),
        headsignIndex >= 0 && values.length > headsignIndex
            ? values[headsignIndex].trim()
            : '',
      );
    }
    return result;
  }

  static Future<Map<String, _RouteInfo>> _loadRoutes(String base) async {
    final rows = (await rootBundle.loadString(
      '$base/routes.txt',
    )).split(RegExp(r'\r?\n'));
    if (rows.isEmpty) return {};
    final header = _csvRow(rows.first);
    final idIndex = header.indexOf('route_id');
    final shortIndex = header.indexOf('route_short_name');
    final longIndex = header.indexOf('route_long_name');
    final result = <String, _RouteInfo>{};
    for (final row in rows.skip(1)) {
      final values = _csvRow(row);
      if (idIndex < 0 || values.length <= idIndex) continue;
      result[values[idIndex].trim()] = _RouteInfo(
        shortIndex >= 0 && values.length > shortIndex
            ? values[shortIndex].trim()
            : '',
        longIndex >= 0 && values.length > longIndex
            ? values[longIndex].trim()
            : '',
      );
    }
    return result;
  }

  static Future<Map<String, List<_FrequencyInfo>>> _loadFrequencies(
      String base,
      ) async {
    try {
      final rows = (await rootBundle.loadString(
        '$base/frequencies.txt',
      )).split(RegExp(r'\r?\n'));
      if (rows.isEmpty) return {};
      final header = _csvRow(rows.first);
      final tripIndex = header.indexOf('trip_id');
      final startIndex = header.indexOf('start_time');
      final endIndex = header.indexOf('end_time');
      final headwayIndex = header.indexOf('headway_secs');
      final exactIndex = header.indexOf('exact_times');
      final required = [
        tripIndex,
        startIndex,
        endIndex,
        headwayIndex,
      ].reduce(math.max);
      if (required < 0) return {};

      final result = <String, List<_FrequencyInfo>>{};
      for (final row in rows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (values.length <= required) continue;
        final start = _timeSeconds(values[startIndex].trim());
        final end = _timeSeconds(values[endIndex].trim());
        final headway = int.tryParse(values[headwayIndex].trim()) ?? 0;
        if (start < 0 || end <= start || headway <= 0) continue;
        final exact =
            exactIndex >= 0 &&
                values.length > exactIndex &&
                values[exactIndex].trim() == '1';
        result
            .putIfAbsent(values[tripIndex].trim(), () => [])
            .add(
          _FrequencyInfo(
            startSeconds: start,
            endSeconds: end,
            headwaySeconds: headway,
            exactTimes: exact,
          ),
        );
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<(Set<String>, String?)> _activeServices(
      String base,
      DateTime date,
      ) async {
    final rows = (await rootBundle.loadString(
      '$base/calendar.txt',
    )).split(RegExp(r'\r?\n'));
    if (rows.isEmpty) return (<String>{}, null);
    final header = _csvRow(rows.first);
    final serviceIndex = header.indexOf('service_id');
    final startIndex = header.indexOf('start_date');
    final endIndex = header.indexOf('end_date');
    final weekdayIndex = switch (date.weekday) {
      DateTime.monday => header.indexOf('monday'),
      DateTime.tuesday => header.indexOf('tuesday'),
      DateTime.wednesday => header.indexOf('wednesday'),
      DateTime.thursday => header.indexOf('thursday'),
      DateTime.friday => header.indexOf('friday'),
      DateTime.saturday => header.indexOf('saturday'),
      _ => header.indexOf('sunday'),
    };
    final today = _dateNumber(date);
    var latestEnd = 0;
    final active = <String>{};
    for (final row in rows.skip(1)) {
      final values = _csvRow(row);
      final needed = [
        serviceIndex,
        startIndex,
        endIndex,
        weekdayIndex,
      ].reduce(math.max);
      if (needed < 0 || values.length <= needed) continue;
      final start = int.tryParse(values[startIndex].trim()) ?? 0;
      final end = int.tryParse(values[endIndex].trim()) ?? 0;
      latestEnd = math.max(latestEnd, end);
      if (today >= start &&
          today <= end &&
          values[weekdayIndex].trim() == '1') {
        active.add(values[serviceIndex].trim());
      }
    }

    try {
      final exceptions = (await rootBundle.loadString(
        '$base/calendar_dates.txt',
      )).split(RegExp(r'\r?\n'));
      if (exceptions.isNotEmpty) {
        final exceptionHeader = _csvRow(exceptions.first);
        final idIndex = exceptionHeader.indexOf('service_id');
        final dateIndex = exceptionHeader.indexOf('date');
        final typeIndex = exceptionHeader.indexOf('exception_type');
        for (final row in exceptions.skip(1)) {
          final values = _csvRow(row);
          final needed = [idIndex, dateIndex, typeIndex].reduce(math.max);
          if (needed < 0 || values.length <= needed) continue;
          if ((int.tryParse(values[dateIndex].trim()) ?? 0) != today) continue;
          final service = values[idIndex].trim();
          if (values[typeIndex].trim() == '1') active.add(service);
          if (values[typeIndex].trim() == '2') active.remove(service);
        }
      }
    } catch (_) {}

    final notice = latestEnd > 0 && today > latestEnd
        ? 'The ${base.split('/').last.replaceAll('_', ' ')} GTFS feed expired '
        'on ${_formatGtfsDate(latestEnd)}. Refresh this dataset from '
        'data.gov.my before using its timetable.'
        : null;
    return (active, notice);
  }

  static int _timeSeconds(String value) {
    final parts = value.split(':');
    if (parts.length < 2) return -1;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0;
    if (hour == null || minute == null) return -1;
    return hour * 3600 + minute * 60 + second;
  }

  static String _displaySeconds(int seconds) {
    final roundedMinutes = (seconds + 30) ~/ 60;
    var hour = (roundedMinutes ~/ 60) % 24;
    final minute = roundedMinutes % 60;
    final suffix = hour >= 12 ? 'PM' : 'AM';
    if (hour == 0) hour = 12;
    if (hour > 12) hour -= 12;
    return '$hour:${minute.toString().padLeft(2, '0')} $suffix';
  }

  static String _frequencyDescription(
      _FrequencyInfo frequency,
      int stationStart,
      int stationEnd,
      ) {
    final minutes = frequency.headwaySeconds / 60;
    final headway = minutes == minutes.roundToDouble()
        ? '${minutes.round()} min'
        : '${minutes.toStringAsFixed(1)} min';
    final qualifier = frequency.exactTimes ? 'Every' : 'Approx. every';
    return '$qualifier $headway • ${_displaySeconds(stationStart)}–'
        '${_displaySeconds(stationEnd)}';
  }

  static String _cleanHeadsign(String value) {
    return value.replaceFirst(RegExp(r'^From\s+', caseSensitive: false), '');
  }

  static int _dateNumber(DateTime date) {
    return date.year * 10000 + date.month * 100 + date.day;
  }

  static String _formatGtfsDate(int value) {
    final text = value.toString().padLeft(8, '0');
    return '${text.substring(0, 4)}-${text.substring(4, 6)}-'
        '${text.substring(6, 8)}';
  }
}

class AddressService {
  static final Map<String, Future<String?>> _memory = {};
  static DateTime? _lastRequest;

  static Future<String?> resolve(Station station) {
    final key =
        '${station.latitude.toStringAsFixed(5)},'
        '${station.longitude.toStringAsFixed(5)}';
    return _memory.putIfAbsent(key, () => _resolve(key, station));
  }

  static Future<String?> _resolve(String key, Station station) async {
    final preferences = await SharedPreferences.getInstance();
    final cached = preferences.getString('station_address_$key');
    if (cached != null && cached.isNotEmpty) return cached;

    if (_lastRequest != null) {
      final wait =
          const Duration(seconds: 1) - DateTime.now().difference(_lastRequest!);
      if (!wait.isNegative) await Future<void>.delayed(wait);
    }
    _lastRequest = DateTime.now();

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': station.latitude.toString(),
        'lon': station.longitude.toString(),
        'zoom': '18',
        'addressdetails': '1',
        'accept-language': 'en,ms',
      });
      final response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'NextRoute-TARUMT-Assignment/1.0',
          'Accept-Language': 'en,ms;q=0.9',
        },
      );
      if (response.statusCode != 200) return station.landmark;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final address = body['display_name']?.toString().trim();
      if (address == null || address.isEmpty) return station.landmark;
      await preferences.setString('station_address_$key', address);
      return address;
    } catch (_) {
      return station.landmark;
    }
  }
}

class RecentStationService {
  static const int maximumItems = 5;

  static String get _storageKey {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return userId == null
        ? 'transport_recent_stations_guest_v1'
        : 'transport_recent_stations_user_${userId}_v1';
  }

  static Future<List<Station>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final names = preferences.getStringList(_storageKey) ?? const [];
    if (names.isEmpty) return [];

    final stations = await StationRepository.instance.loadAll();
    final byName = {
      for (final station in stations) _stationKey(station): station,
    };
    return names
        .map((name) => byName[name])
        .whereType<Station>()
        .take(maximumItems)
        .toList();
  }

  static Future<void> add(Station station) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _stationKey(station);
    final current = preferences.getStringList(_storageKey) ?? <String>[];
    final updated = <String>[
      key,
      ...current.where((item) => item != key),
    ].take(maximumItems).toList();
    await preferences.setStringList(_storageKey, updated);
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);
  }

  static String _stationKey(Station station) {
    return station.name.trim().toUpperCase();
  }
}

Future<void> openStationDetails(BuildContext context, Station station) async {
  try {
    await RecentStationService.add(station);
  } catch (_) {
    // Local history must never prevent the user from opening station details.
  }
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => StationDetailScreen(station: station)),
  );
}

Future<void> openGoogleMaps(Station station) async {
  final position = await DeviceLocationService.currentLocation();
  final latitude = position.latitude;
  final longitude = position.longitude;
  if (!isInsideMalaysia(latitude, longitude)) {
    throw Exception(locationOutsideCoverageMessage(latitude, longitude));
  }
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'origin': '$latitude,$longitude',
    'destination': '${station.latitude},${station.longitude}',
    'travelmode': 'transit',
    'dir_action': 'navigate',
  });
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    throw Exception('Could not open Google Maps.');
  }
}

const fallbackStations = <Station>[
  Station('KL Sentral', 0.2, ['KJ', 'PY', 'KT', 'MR', 'EL']),
  Station('Masjid Jamek', 1.4, ['KJ', 'AG']),
  Station('KLCC', 2.8, ['KJ']),
  Station('Bukit Bintang', 1.9, ['MR']),
  Station('Pasar Seni', 1.1, ['KJ', 'KG']),
  Station('Bangsar', 3.5, ['PY']),
  Station('Bank Negara', 3.2, ['KT']),
];

class StationRepository {
  StationRepository._();

  static final StationRepository instance = StationRepository._();
  List<Station>? _cache;

  Future<List<Station>> loadAll() async {
    if (_cache != null) return _cache!;

    final all = <Station>[];
    all.addAll(await _loadRail());
    all.addAll(
      await _loadStops(
        'assets/gtfs/bus/stops.txt',
        nameIndex: 1,
        latitudeIndex: 3,
        longitudeIndex: 4,
        type: 'Bus',
        line: 'BUS',
        source: 'bus',
        descriptionIndex: 2,
      ),
    );
    all.addAll(
      await _loadStops(
        'assets/gtfs/mrt_feeder/stops.txt',
        nameIndex: 2,
        latitudeIndex: 3,
        longitudeIndex: 4,
        type: 'MRT Feeder',
        line: 'T',
        source: 'mrt_feeder',
      ),
    );

    final merged = <String, Station>{};
    for (final station in all) {
      final key = station.name.trim().toUpperCase();
      final existing = merged[key];
      if (existing == null) {
        merged[key] = station;
      } else {
        merged[key] = Station(
          existing.name,
          math.min(existing.distance, station.distance),
          {...existing.lines, ...station.lines}.toList(),
          latitude: existing.latitude,
          longitude: existing.longitude,
          type: existing.type == station.type
              ? existing.type
              : '${existing.type} / ${station.type}',
          accessible: existing.accessible == true || station.accessible == true
              ? true
              : existing.accessible ?? station.accessible,
          stopIds: {...existing.stopIds, ...station.stopIds}.toList(),
          sources: {...existing.sources, ...station.sources}.toList(),
          landmark: existing.landmark ?? station.landmark,
        );
      }
    }

    _cache = merged.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return _cache!;
  }

  Future<List<Station>> _loadRail() async {
    final raw = await rootBundle.loadString('assets/gtfs/rail/stops.txt');
    final result = <Station>[];
    for (final row in raw.split(RegExp(r'\r?\n')).skip(1)) {
      if (row.trim().isEmpty) continue;
      final values = _csvRow(row);
      if (values.length < 6) continue;
      final latitude = double.tryParse(values[2]) ?? 0;
      final longitude = double.tryParse(values[3]) ?? 0;
      result.add(
        Station(
          _displayName(values[1]),
          double.infinity,
          [values[5].trim().toUpperCase()],
          latitude: latitude,
          longitude: longitude,
          type: values[4].trim().isEmpty ? 'Rail' : values[4].trim(),
          accessible: values.length > 7
              ? values[7].trim().toLowerCase() == 'true'
              : null,
          stopIds: [values[0].trim()],
          sources: const ['rail'],
        ),
      );
    }
    return result;
  }

  Future<List<Station>> _loadStops(
      String asset, {
        required int nameIndex,
        required int latitudeIndex,
        required int longitudeIndex,
        required String type,
        required String line,
        required String source,
        int? descriptionIndex,
      }) async {
    final raw = await rootBundle.loadString(asset);
    final result = <Station>[];
    for (final row in raw.split(RegExp(r'\r?\n')).skip(1)) {
      if (row.trim().isEmpty) continue;
      final values = _csvRow(row);
      if (values.length <= longitudeIndex) continue;
      final latitude = double.tryParse(values[latitudeIndex]) ?? 0;
      final longitude = double.tryParse(values[longitudeIndex]) ?? 0;
      final name = _displayName(values[nameIndex]);
      if (name.toUpperCase().contains('REDONE')) continue;
      result.add(
        Station(
          name,
          double.infinity,
          [line],
          latitude: latitude,
          longitude: longitude,
          type: type,
          stopIds: [values[0].trim()],
          sources: [source],
          landmark: descriptionIndex != null && values.length > descriptionIndex
              ? values[descriptionIndex].trim()
              : null,
        ),
      );
    }
    return result;
  }

  List<String> _csvRow(String row) {
    final values = <String>[];
    final buffer = StringBuffer();
    var quoted = false;
    for (var i = 0; i < row.length; i++) {
      final char = row[i];
      if (char == '"') {
        if (quoted && i + 1 < row.length && row[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (char == ',' && !quoted) {
        values.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }
    values.add(buffer.toString().trim());
    return values;
  }

  String _displayName(String value) {
    final cleaned = value
        .replaceFirst(RegExp(r'^\([A-Z]\)\s*', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^[A-Z]{1,3}\d{2,6}\s+'), '')
        .replaceFirst(RegExp(r'\s*-\s*REDONE$', caseSensitive: false), '');
    const acronyms = {'KL', 'MRT', 'LRT', 'BRT', 'KTM', 'TNB', 'UKM', 'UM'};
    return cleaned
        .trim()
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .map((word) {
      final upper = word.toUpperCase();
      if (acronyms.contains(upper)) return upper;
      return word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1)}';
    })
        .join(' ');
  }
}

Color lineColor(String line) {
  return switch (line) {
    'KJ' => const Color(0xFFEF4444),
    'PY' => const Color(0xFF0D9488),
    'KT' => const Color(0xFF16A34A),
    'MR' => const Color(0xFFE17A00),
    'EL' => const Color(0xFF6366F1),
    'AG' => const Color(0xFF8B5CF6),
    'KG' => const Color(0xFFF97316),
    'BUS' => const Color(0xFF3B82F6),
    'T' => const Color(0xFF06B6D4),
    _ => Colors.blueGrey,
  };
}

class TransportDataScreen extends StatefulWidget {
  const TransportDataScreen({super.key});

  @override
  State<TransportDataScreen> createState() => _TransportDataScreenState();
}

class _TransportDataScreenState extends State<TransportDataScreen> {
  List<Station> nearbyPreview = [];
  List<Station> recentSearches = [];
  bool loadingPreview = true;
  bool loadingRecentSearches = true;
  String? previewMessage;

  @override
  void initState() {
    super.initState();
    _loadNearbyPreview();
    _loadRecentSearches();
  }

  Future<void> _loadRecentSearches() async {
    try {
      final loaded = await RecentStationService.load();
      if (!mounted) return;
      setState(() {
        recentSearches = loaded;
        loadingRecentSearches = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => loadingRecentSearches = false);
    }
  }

  Future<void> _clearRecentSearches() async {
    await RecentStationService.clear();
    if (!mounted) return;
    setState(() => recentSearches = []);
  }

  Future<void> _loadNearbyPreview() async {
    if (mounted) {
      setState(() {
        loadingPreview = true;
        previewMessage = null;
      });
    }
    try {
      final position = await DeviceLocationService.currentLocation();
      final latitude = position.latitude;
      final longitude = position.longitude;
      if (!isInsideMalaysia(latitude, longitude)) {
        throw Exception(locationOutsideCoverageMessage(latitude, longitude));
      }
      final stations = await StationRepository.instance.loadAll();
      final sorted =
      stations
          .where(
            (station) => station.latitude != 0 && station.longitude != 0,
      )
          .map(
            (station) => station.withDistance(
          distanceKm(
            latitude,
            longitude,
            station.latitude,
            station.longitude,
          ),
        ),
      )
          .toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));
      if (sorted.isEmpty || sorted.first.distance > 100) {
        throw Exception(locationOutsideCoverageMessage(latitude, longitude));
      }
      if (!mounted) return;
      setState(() {
        nearbyPreview = sorted.take(3).toList();
        loadingPreview = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loadingPreview = false;
        previewMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    await _loadRecentSearches();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: _blue,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 46),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Transport Information',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Find Your Station',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Transform.translate(
                offset: const Offset(0, -22),
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children: [
                    _SearchCard(onTap: () => open(const StationSearchScreen())),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.location_on_outlined,
                            label: 'Nearby Stations',
                            color: const Color(0xFF059669),
                            onTap: () => open(const NearbyStationsScreen()),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: _ActionCard(
                            icon: Icons.map_outlined,
                            label: 'View Map',
                            color: const Color(0xFF7C3AED),
                            onTap: () => open(const TransitMapScreen()),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'NEAREST STATIONS',
                          style: TextStyle(
                            color: Color(0xFF71839E),
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                          ),
                        ),
                        TextButton(
                          onPressed: loadingPreview ? null : _loadNearbyPreview,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                    if (loadingPreview)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (nearbyPreview.isNotEmpty)
                      StationListCard(items: nearbyPreview)
                    else if (previewMessage != null)
                        _MessageCard(
                          icon: Icons.location_off_outlined,
                          color: Colors.orange,
                          message: previewMessage!,
                          actionLabel: 'Try again',
                          onAction: _loadNearbyPreview,
                        ),
                    if (!loadingRecentSearches &&
                        recentSearches.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'RECENT SEARCHES',
                            style: TextStyle(
                              color: Color(0xFF71839E),
                              fontWeight: FontWeight.w700,
                              letterSpacing: .8,
                            ),
                          ),
                          TextButton(
                            onPressed: _clearRecentSearches,
                            child: const Text('Clear all'),
                          ),
                        ],
                      ),
                      StationListCard(
                        items: recentSearches,
                        onHistoryChanged: _loadRecentSearches,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SearchCard({required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 2,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: const Padding(
        padding: EdgeInsets.all(18),
        child: Row(
          children: [
            _SoftIcon(Icons.search, _blue),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Search Station',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Find any station by name or line',
                  style: TextStyle(color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 22),
        child: Column(
          children: [
            _SoftIcon(icon, color),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SoftIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _SoftIcon(this.icon, this.color);
  @override
  Widget build(BuildContext context) => Container(
    width: 54,
    height: 54,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .09),
      borderRadius: BorderRadius.circular(15),
    ),
    child: Icon(icon, color: color, size: 28),
  );
}

class StationListCard extends StatelessWidget {
  final List<Station> items;
  final Future<void> Function()? onHistoryChanged;

  const StationListCard({
    super.key,
    required this.items,
    this.onHistoryChanged,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: .06), blurRadius: 8),
      ],
    ),
    child: Column(
      children: List.generate(items.length, (index) {
        final station = items[index];
        return Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              leading: _SoftIcon(
                Icons.my_location,
                lineColor(station.lines.first),
              ),
              title: Text(
                station.name,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 5,
                  children: station.lines.map((e) => LineBadge(e)).toList(),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (station.hasDistance) ...[
                    Text(
                      station.distance < 1
                          ? '${(station.distance * 1000).round()} m'
                          : '${station.distance.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                ],
              ),
              onTap: () async {
                await openStationDetails(context, station);
                await onHistoryChanged?.call();
              },
            ),
            if (index != items.length - 1)
              const Divider(height: 1, indent: 18, endIndent: 18),
          ],
        );
      }),
    ),
  );
}

class LineBadge extends StatelessWidget {
  final String code;
  const LineBadge(this.code, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: lineColor(code),
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      code,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

class StationSearchScreen extends StatefulWidget {
  const StationSearchScreen({super.key});
  @override
  State<StationSearchScreen> createState() => _StationSearchScreenState();
}

class _StationSearchScreenState extends State<StationSearchScreen> {
  String query = '';
  List<Station> allStations = [];
  bool loading = true;
  String? locationMessage;

  @override
  void initState() {
    super.initState();
    _loadStations();
  }

  Future<void> _loadStations() async {
    final loaded = await StationRepository.instance.loadAll();
    List<Station> located = loaded;
    String? message;
    try {
      final position = await DeviceLocationService.currentLocation();
      final latitude = position.latitude;
      final longitude = position.longitude;
      if (!isInsideMalaysia(latitude, longitude)) {
        message = locationOutsideCoverageMessage(latitude, longitude);
      } else {
        located =
        loaded
            .where(
              (station) => station.latitude != 0 && station.longitude != 0,
        )
            .map(
              (station) => station.withDistance(
            distanceKm(
              latitude,
              longitude,
              station.latitude,
              station.longitude,
            ),
          ),
        )
            .toList()
          ..sort((a, b) => a.distance.compareTo(b.distance));
        if (located.isEmpty || located.first.distance > 100) {
          message = locationOutsideCoverageMessage(latitude, longitude);
          located = loaded;
        }
      }
    } catch (error) {
      message = error.toString().replaceFirst('Exception: ', '');
    }
    if (!mounted) return;
    setState(() {
      allStations = located;
      locationMessage = message;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final result =
    normalizedQuery.isEmpty
        ? allStations
        .where((station) => station.hasDistance)
        .take(12)
        .toList()
        : allStations.where((station) {
      return station.name.toLowerCase().contains(normalizedQuery) ||
          station.type.toLowerCase().contains(normalizedQuery) ||
          station.lines.any(
                (line) => line.toLowerCase().contains(normalizedQuery),
          );
    }).toList()
      ..sort((a, b) {
        final aExact = a.name.toLowerCase() == normalizedQuery ? 0 : 1;
        final bExact = b.name.toLowerCase() == normalizedQuery ? 0 : 1;
        if (aExact != bExact) return aExact.compareTo(bExact);
        if (a.hasDistance && b.hasDistance) {
          return a.distance.compareTo(b.distance);
        }
        return a.name.compareTo(b.name);
      });
    return Scaffold(
      backgroundColor: _page,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: _blue,
              padding: const EdgeInsets.fromLTRB(14, 12, 18, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: Navigator.of(context).pop,
                    icon: const Icon(Icons.chevron_left, color: Colors.white),
                    label: const Text(
                      'Back',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      'Search Station',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    autofocus: false,
                    onChanged: (value) => setState(() => query = value),
                    decoration: InputDecoration(
                      hintText: 'Station name or line...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  Text(
                    normalizedQuery.isEmpty
                        ? 'NEAREST STATIONS'
                        : '${result.length} RESULT${result.length == 1 ? '' : 'S'}',
                    style: const TextStyle(
                      color: Color(0xFF71839E),
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (locationMessage != null && normalizedQuery.isEmpty) ...[
                    _MessageCard(
                      icon: Icons.location_off_outlined,
                      color: Colors.orange.shade800,
                      message: locationMessage!,
                      actionLabel: 'Try location again',
                      onAction: () {
                        setState(() {
                          loading = true;
                          locationMessage = null;
                        });
                        _loadStations();
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (result.isEmpty &&
                      normalizedQuery.isEmpty &&
                      locationMessage != null)
                    const SizedBox.shrink()
                  else if (result.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 80),
                        child: Center(
                          child: Text(
                            'No station found',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      StationListCard(items: result),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NearbyStationsScreen extends StatefulWidget {
  const NearbyStationsScreen({super.key});
  @override
  State<NearbyStationsScreen> createState() => _NearbyStationsScreenState();
}

class _NearbyStationsScreenState extends State<NearbyStationsScreen> {
  bool detected = false;
  bool loading = false;
  bool tracking = false;
  List<Station> nearest = [];
  loc.LocationData? currentPosition;
  String? errorMessage;
  StreamSubscription<loc.LocationData>? locationSubscription;

  Future<void> _detectLocation() async {
    setState(() {
      loading = true;
      errorMessage = null;
    });
    try {
      final position = await DeviceLocationService.currentLocation();
      final valid = await _updateNearest(position);
      if (!valid) {
        if (!mounted) return;
        setState(() => loading = false);
        return;
      }
      await locationSubscription?.cancel();
      locationSubscription = DeviceLocationService.locationStream().listen(
        _updateNearest,
        onError: (Object error) {
          if (!mounted) return;
          setState(() => errorMessage = error.toString());
        },
      );
      if (!mounted) return;
      setState(() {
        loading = false;
        detected = true;
        tracking = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<bool> _updateNearest(loc.LocationData position) async {
    final latitude = position.latitude;
    final longitude = position.longitude;
    if (!isInsideMalaysia(latitude, longitude)) {
      if (mounted) {
        setState(() {
          errorMessage = locationOutsideCoverageMessage(latitude, longitude);
          detected = false;
          nearest = [];
        });
      }
      return false;
    }
    final loaded = await StationRepository.instance.loadAll();
    final sorted =
    loaded
        .where((station) => station.latitude != 0 && station.longitude != 0)
        .map(
          (station) => station.withDistance(
        distanceKm(
          latitude,
          longitude,
          station.latitude,
          station.longitude,
        ),
      ),
    )
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));
    if (sorted.isEmpty || sorted.first.distance > 100) {
      if (mounted) {
        setState(() {
          errorMessage = locationOutsideCoverageMessage(latitude, longitude);
          detected = false;
          nearest = [];
        });
      }
      return false;
    }
    if (!mounted) return false;
    setState(() {
      currentPosition = position;
      nearest = sorted
          .where((station) => station.distance <= 25)
          .take(15)
          .toList();
    });
    return true;
  }

  Future<void> _stopTracking() async {
    await locationSubscription?.cancel();
    locationSubscription = null;
    if (!mounted) return;
    setState(() => tracking = false);
  }

  @override
  void dispose() {
    locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _page,
    body: SafeArea(
      child: Column(
        children: [
          _SimpleHeader(
            title: 'Nearby Stations',
            subtitle: 'Detect your current location to see nearby stations',
            color: const Color(0xFF07835F),
          ),
          Expanded(
            child: detected
                ? ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Text(
                  currentPosition == null
                      ? 'NEAREST TO YOU'
                      : 'NEAREST TO YOUR LIVE LOCATION',
                  style: const TextStyle(
                    color: Color(0xFF71839E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                if (currentPosition?.accuracy != null) ...[
                  Text(
                    'GPS accuracy: ±${currentPosition!.accuracy!.round()} m',
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                ],
                OutlinedButton.icon(
                  onPressed: tracking ? _stopTracking : _detectLocation,
                  icon: Icon(
                    tracking
                        ? Icons.stop_circle_outlined
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    tracking
                        ? 'Stop Location Tracking'
                        : 'Start Tracking',
                  ),
                ),
                const SizedBox(height: 12),
                StationListCard(items: nearest),
              ],
            )
                : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const _SoftIcon(
                      Icons.location_on_outlined,
                      Color(0xFF059669),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Enable Location',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'We need your location to find the nearest transport stations',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF7C8DA6),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 28),
                    if (errorMessage != null) ...[
                      Text(
                        errorMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.red),
                      ),
                      const SizedBox(height: 16),
                    ],
                    ElevatedButton.icon(
                      onPressed: loading ? null : _detectLocation,
                      icon: loading
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : const Icon(
                        Icons.my_location,
                        color: Colors.white,
                      ),
                      label: Text(
                        loading
                            ? 'Loading Stations...'
                            : 'Detect My Location',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 28,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _SimpleHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  const _SimpleHeader({
    required this.title,
    required this.subtitle,
    required this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: color,
    padding: const EdgeInsets.fromLTRB(14, 10, 20, 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: Navigator.of(context).pop,
          icon: const Icon(Icons.chevron_left, color: Colors.white),
          label: const Text('Back', style: TextStyle(color: Colors.white)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        ),
      ],
    ),
  );
}

class _TransitRoutePicker extends StatefulWidget {
  final String serviceName;
  final List<TransitRoute> routes;
  final TransitRoute? selectedRoute;

  const _TransitRoutePicker({
    required this.serviceName,
    required this.routes,
    required this.selectedRoute,
  });

  @override
  State<_TransitRoutePicker> createState() => _TransitRoutePickerState();
}

class _TransitRoutePickerState extends State<_TransitRoutePicker> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final normalizedQuery = query.trim().toLowerCase();
    final filtered = widget.routes.where((route) {
      if (normalizedQuery.isEmpty) return true;
      return route.displayName.toLowerCase().contains(normalizedQuery) ||
          route.description.toLowerCase().contains(normalizedQuery);
    }).toList();

    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 650),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Choose a ${widget.serviceName} route',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: Navigator.of(context).pop,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const Text(
                'The map will show stops and live vehicles for the selected route.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              TextField(
                autofocus: true,
                onChanged: (value) => setState(() => query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search by route number or destination',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matching bus route found.'))
                    : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final route = filtered[index];
                    final selected = widget.selectedRoute?.id == route.id;
                    return ListTile(
                      selected: selected,
                      leading: Container(
                        constraints: const BoxConstraints(minWidth: 54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? _blue
                              : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          route.displayName,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected ? Colors.white : _blue,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      title: Text(
                        route.description.isEmpty
                            ? '${widget.serviceName} route ${route.displayName}'
                            : route.description,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text('${route.stopIds.length} stops'),
                      trailing: selected
                          ? const Icon(Icons.check, color: _blue)
                          : const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pop(context, route),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _RoadService { rapidKlBus, mrtFeeder }

extension on _RoadService {
  String get label => switch (this) {
    _RoadService.rapidKlBus => 'Rapid KL Bus',
    _RoadService.mrtFeeder => 'MRT Feeder',
  };

  String get stationSource => switch (this) {
    _RoadService.rapidKlBus => 'bus',
    _RoadService.mrtFeeder => 'mrt_feeder',
  };

  String get assetPath => switch (this) {
    _RoadService.rapidKlBus => 'assets/gtfs/bus',
    _RoadService.mrtFeeder => 'assets/gtfs/mrt_feeder',
  };

  String get realtimeCategory => switch (this) {
    _RoadService.rapidKlBus => 'rapid-bus-kl',
    _RoadService.mrtFeeder => 'rapid-bus-mrtfeeder',
  };

  Color get color => switch (this) {
    _RoadService.rapidKlBus => const Color(0xFF2563EB),
    _RoadService.mrtFeeder => const Color(0xFF0891B2),
  };
}

class TransitMapScreen extends StatefulWidget {
  const TransitMapScreen({super.key});

  @override
  State<TransitMapScreen> createState() => _TransitMapScreenState();
}

class _TransitMapScreenState extends State<TransitMapScreen> {
  final MapController mapController = MapController();
  List<Station> visibleStations = [];
  List<LiveVehicle> vehicles = [];
  List<TransitRoute> rapidBusRoutes = [];
  List<TransitRoute> feederRoutes = [];
  List<RailShape> railShapes = [];
  TransitRoute? selectedRoadRoute;
  _RoadService? selectedRoadService;
  loc.LocationData? position;
  StreamSubscription<loc.LocationData>? locationSubscription;
  Timer? vehicleRefreshTimer;
  bool loading = true;
  bool showRail = true;
  bool showVehicles = false;
  bool refreshingVehicles = false;
  String? liveError;
  String? locationWarning;

  @override
  void initState() {
    super.initState();
    _loadMap();
  }

  Future<void> _loadMap() async {
    final allStations = await StationRepository.instance.loadAll();
    final availableBusRoutes = await TransitRouteRepository.load(
      _RoadService.rapidKlBus.assetPath,
    );
    final availableFeederRoutes = await TransitRouteRepository.load(
      _RoadService.mrtFeeder.assetPath,
    );
    final availableRailShapes = await RailShapeRepository.load();
    loc.LocationData? detectedPosition;
    try {
      final candidate = await DeviceLocationService.currentLocation();
      if (isInsideMalaysia(candidate.latitude, candidate.longitude)) {
        detectedPosition = candidate;
        locationSubscription = DeviceLocationService.locationStream().listen((
            data,
            ) {
          if (!mounted || !isInsideMalaysia(data.latitude, data.longitude)) {
            return;
          }
          setState(() => position = data);
        });
      } else {
        locationWarning = locationOutsideCoverageMessage(
          candidate.latitude,
          candidate.longitude,
        );
      }
    } catch (error) {
      locationWarning = error.toString().replaceFirst('Exception: ', '');
    }

    var centreLatitude = 3.1390;
    var centreLongitude = 101.6869;
    if (detectedPosition != null) {
      centreLatitude = detectedPosition.latitude;
      centreLongitude = detectedPosition.longitude;
    }

    final nearby =
    allStations
        .where((station) => station.latitude != 0 && station.longitude != 0)
        .map(
          (station) => station.withDistance(
        distanceKm(
          centreLatitude,
          centreLongitude,
          station.latitude,
          station.longitude,
        ),
      ),
    )
        .toList()
      ..sort((a, b) => a.distance.compareTo(b.distance));

    if (!mounted) return;
    setState(() {
      position = detectedPosition;
      visibleStations = nearby;
      rapidBusRoutes = availableBusRoutes;
      feederRoutes = availableFeederRoutes;
      railShapes = availableRailShapes;
      loading = false;
    });
  }

  Future<void> _refreshVehicles() async {
    final service = selectedRoadService;
    if (service == null || refreshingVehicles) return;
    refreshingVehicles = true;
    if (mounted) setState(() => liveError = null);
    try {
      final latest = await RealtimeVehicleService.loadPrasaranaVehicles(
        service.realtimeCategory,
      );
      if (!mounted || selectedRoadService != service) return;
      setState(() => vehicles = latest);
    } catch (error) {
      if (!mounted || selectedRoadService != service) return;
      setState(() {
        liveError = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      refreshingVehicles = false;
      if (mounted) setState(() {});
    }
  }

  void _startVehicleRefresh() {
    vehicleRefreshTimer?.cancel();
    vehicleRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
          (_) => _refreshVehicles(),
    );
  }

  void _stopVehicleRefresh() {
    vehicleRefreshTimer?.cancel();
    vehicleRefreshTimer = null;
  }

  Future<void> _toggleRoadService(_RoadService service, bool value) async {
    if (!value) {
      _stopVehicleRefresh();
      setState(() {
        selectedRoadService = null;
        selectedRoadRoute = null;
        showVehicles = false;
        vehicles = [];
        liveError = null;
      });
      return;
    }

    final serviceChanged = selectedRoadService != service;
    _stopVehicleRefresh();
    setState(() {
      showRail = false;
      selectedRoadService = service;
      if (serviceChanged) selectedRoadRoute = null;
      showVehicles = false;
      vehicles = [];
      liveError = null;
    });
    if (selectedRoadRoute == null) await _chooseRoadRoute(service);
  }

  void _toggleRail(bool value) {
    _stopVehicleRefresh();
    setState(() {
      showRail = value;
      if (value) {
        selectedRoadService = null;
        selectedRoadRoute = null;
        showVehicles = false;
        vehicles = [];
        liveError = null;
      }
    });
  }

  Future<void> _chooseRoadRoute(_RoadService service) async {
    final routes = service == _RoadService.rapidKlBus
        ? rapidBusRoutes
        : feederRoutes;
    final choice = await showDialog<TransitRoute>(
      context: context,
      builder: (dialogContext) => _TransitRoutePicker(
        serviceName: service.label,
        routes: routes,
        selectedRoute: selectedRoadService == service
            ? selectedRoadRoute
            : null,
      ),
    );
    if (!mounted || choice == null) return;
    setState(() {
      showRail = false;
      selectedRoadService = service;
      selectedRoadRoute = choice;
      showVehicles = true;
    });
    _startVehicleRefresh();
    await _refreshVehicles();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitStations(
        visibleStations.where(_stationMatchesSelectedRoadRoute).toList(),
      );
    });
  }

  void _toggleLiveVehicles(bool value) {
    setState(() => showVehicles = value);
    if (value) {
      _startVehicleRefresh();
      _refreshVehicles();
    } else {
      _stopVehicleRefresh();
    }
  }

  void _fitStations(List<Station> stations) {
    if (stations.isEmpty) return;
    var minimumLatitude = stations.first.latitude;
    var maximumLatitude = stations.first.latitude;
    var minimumLongitude = stations.first.longitude;
    var maximumLongitude = stations.first.longitude;
    for (final station in stations.skip(1)) {
      minimumLatitude = math.min(minimumLatitude, station.latitude);
      maximumLatitude = math.max(maximumLatitude, station.latitude);
      minimumLongitude = math.min(minimumLongitude, station.longitude);
      maximumLongitude = math.max(maximumLongitude, station.longitude);
    }
    final span = math.max(
      maximumLatitude - minimumLatitude,
      maximumLongitude - minimumLongitude,
    );
    final zoom = switch (span) {
      > 1.2 => 8.0,
      > .7 => 9.0,
      > .35 => 10.0,
      > .18 => 11.0,
      > .09 => 12.0,
      > .045 => 13.0,
      _ => 14.0,
    };
    mapController.move(
      LatLng(
        (minimumLatitude + maximumLatitude) / 2,
        (minimumLongitude + maximumLongitude) / 2,
      ),
      zoom,
    );
  }

  bool _stationMatchesSelectedRoadRoute(Station station) {
    final service = selectedRoadService;
    final route = selectedRoadRoute;
    if (service == null || route == null) return false;
    if (!station.sources.contains(service.stationSource)) return false;
    return station.stopIds.any(route.stopIds.contains);
  }

  bool _vehicleMatchesSelectedRoadRoute(LiveVehicle vehicle) {
    final route = selectedRoadRoute;
    if (route == null) return false;
    final vehicleRoute = vehicle.routeId.trim().toUpperCase();
    return vehicleRoute == route.id.trim().toUpperCase() ||
        vehicleRoute == route.displayName.toUpperCase();
  }

  @override
  void dispose() {
    _stopVehicleRefresh();
    locationSubscription?.cancel();
    mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final centre = position == null
        ? const LatLng(3.1390, 101.6869)
        : LatLng(position!.latitude, position!.longitude);
    final filteredStations = visibleStations.where((station) {
      final matchesRail = showRail && station.sources.contains('rail');
      final matchesRoad =
          selectedRoadService != null &&
              _stationMatchesSelectedRoadRoute(station);
      return matchesRail || matchesRoad;
    }).toList();
    final filteredVehicles = vehicles
        .where(_vehicleMatchesSelectedRoadRoute)
        .toList();
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const _SimpleHeader(
              title: 'Transit Map',
              subtitle: 'Select rail or a bus route to explore the network',
              color: Color(0xFF6D28D9),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : Stack(
                children: [
                  FlutterMap(
                    mapController: mapController,
                    options: MapOptions(
                      initialCenter: centre,
                      initialZoom: 13,
                    ),
                    children: [
                      TileLayer(
                        urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                        'com.example.nextroute_assignment',
                      ),
                      if (showRail && railShapes.isNotEmpty)
                        PolylineLayer(
                          polylines: railShapes
                              .map(
                                (shape) => Polyline(
                              points: shape.points,
                              color: shape.color.withValues(
                                alpha: .78,
                              ),
                              strokeWidth: 4,
                            ),
                          )
                              .toList(),
                        ),
                      if (filteredStations.isNotEmpty)
                        MarkerLayer(
                          markers: filteredStations.map((station) {
                            final isRoadStop =
                                selectedRoadService != null &&
                                    _stationMatchesSelectedRoadRoute(station);
                            final markerColor = isRoadStop
                                ? selectedRoadService!.color
                                : const Color(0xFF7C3AED);
                            final markerIcon = isRoadStop
                                ? Icons.directions_bus
                                : Icons.train;
                            final routeText = isRoadStop
                                ? selectedRoadRoute?.displayName
                                : null;
                            return Marker(
                              point: LatLng(
                                station.latitude,
                                station.longitude,
                              ),
                              width: 42,
                              height: 42,
                              child: Tooltip(
                                message: routeText == null
                                    ? station.name
                                    : '${station.name}\n'
                                    '${selectedRoadService!.label} '
                                    'route $routeText',
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: markerColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 2.5,
                                    ),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Colors.black26,
                                        blurRadius: 5,
                                        offset: Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: IconButton(
                                    tooltip: station.name,
                                    padding: EdgeInsets.zero,
                                    onPressed: () => openStationDetails(
                                      context,
                                      station,
                                    ),
                                    icon: Icon(
                                      markerIcon,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (selectedRoadService != null &&
                          selectedRoadRoute != null &&
                          showVehicles)
                        MarkerLayer(
                          markers: filteredVehicles.map((vehicle) {
                            return Marker(
                              point: LatLng(
                                vehicle.latitude,
                                vehicle.longitude,
                              ),
                              width: 38,
                              height: 38,
                              child: Tooltip(
                                message:
                                'Bus ${vehicle.id}\nRoute ${vehicle.routeId}',
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color:
                                    selectedRoadService ==
                                        _RoadService.mrtFeeder
                                        ? const Color(0xFF0F766E)
                                        : Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.directions_bus,
                                    color: Colors.white,
                                    size: 23,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      if (position != null)
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: centre,
                              width: 44,
                              height: 44,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(blurRadius: 8)],
                                ),
                                child: Icon(
                                  Icons.my_location,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                      RichAttributionWidget(
                        attributions: [
                          TextSourceAttribution(
                            'OpenStreetMap contributors',
                            onTap: () => launchUrl(
                              Uri.parse(
                                'https://www.openstreetmap.org/copyright',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Positioned(
                    left: 10,
                    right: 10,
                    top: 10,
                    child: Card(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('Rail'),
                              selected: showRail,
                              onSelected: _toggleRail,
                            ),
                            const SizedBox(width: 6),
                            FilterChip(
                              avatar: const Icon(
                                Icons.directions_bus,
                                size: 18,
                              ),
                              label: const Text('Bus routes & stops'),
                              selected:
                              selectedRoadService ==
                                  _RoadService.rapidKlBus,
                              selectedColor: const Color(0xFFBFDBFE),
                              side: BorderSide(
                                color:
                                selectedRoadService ==
                                    _RoadService.rapidKlBus
                                    ? _blue
                                    : const Color(0xFFCBD5E1),
                                width:
                                selectedRoadService ==
                                    _RoadService.rapidKlBus
                                    ? 1.5
                                    : 1,
                              ),
                              onSelected: (value) => _toggleRoadService(
                                _RoadService.rapidKlBus,
                                value,
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilterChip(
                              avatar: const Icon(
                                Icons.airport_shuttle,
                                size: 18,
                              ),
                              label: const Text('MRT feeder'),
                              selected:
                              selectedRoadService ==
                                  _RoadService.mrtFeeder,
                              selectedColor: const Color(0xFFCFFAFE),
                              onSelected: (value) => _toggleRoadService(
                                _RoadService.mrtFeeder,
                                value,
                              ),
                            ),
                            if (selectedRoadService != null) ...[
                              const SizedBox(width: 6),
                              InputChip(
                                avatar: const Icon(
                                  Icons.alt_route,
                                  size: 17,
                                ),
                                label: Text(
                                  selectedRoadRoute == null
                                      ? 'Choose a '
                                      '${selectedRoadService!.label} route'
                                      : selectedRoadRoute!
                                      .description
                                      .isEmpty
                                      ? 'Route '
                                      '${selectedRoadRoute!.displayName}'
                                      : 'Route '
                                      '${selectedRoadRoute!.displayName}: '
                                      '${selectedRoadRoute!.description}',
                                ),
                                backgroundColor: const Color(0xFFFFF7ED),
                                selectedColor: const Color(0xFFDBEAFE),
                                side: BorderSide(
                                  color: selectedRoadRoute == null
                                      ? const Color(0xFFF59E0B)
                                      : selectedRoadService!.color,
                                  width: 1.5,
                                ),
                                selected: selectedRoadRoute != null,
                                onPressed: () => _chooseRoadRoute(
                                  selectedRoadService!,
                                ),
                                onDeleted: selectedRoadRoute == null
                                    ? null
                                    : () {
                                  _stopVehicleRefresh();
                                  setState(() {
                                    selectedRoadRoute = null;
                                    showVehicles = false;
                                    vehicles = [];
                                    liveError = null;
                                  });
                                },
                              ),
                            ],
                            if (selectedRoadService != null &&
                                selectedRoadRoute != null) ...[
                              const SizedBox(width: 6),
                              FilterChip(
                                avatar: const Icon(
                                  Icons.directions_bus,
                                  size: 17,
                                ),
                                label: Text(
                                  'Live buses on '
                                      '${selectedRoadRoute!.displayName} '
                                      '(${filteredVehicles.length})',
                                ),
                                selected: showVehicles,
                                selectedColor: const Color(0xFFFED7AA),
                                onSelected: _toggleLiveVehicles,
                              ),
                              IconButton(
                                tooltip:
                                'Refresh live buses on route '
                                    '${selectedRoadRoute!.displayName}',
                                onPressed: refreshingVehicles
                                    ? null
                                    : _refreshVehicles,
                                icon: refreshingVehicles
                                    ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                                    : const Icon(Icons.refresh),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    bottom: 20,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        FloatingActionButton.small(
                          heroTag: 'map_fit_stops',
                          tooltip: 'Show all visible stops',
                          onPressed: () => _fitStations(filteredStations),
                          child: const Icon(Icons.zoom_out_map),
                        ),
                        const SizedBox(height: 10),
                        FloatingActionButton.small(
                          heroTag: 'map_recentre',
                          tooltip: position == null
                              ? 'Klang Valley overview'
                              : 'My location',
                          onPressed: () => mapController.move(centre, 13),
                          child: Icon(
                            position == null
                                ? Icons.home_work
                                : Icons.my_location,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (locationWarning != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 78,
                      child: _MapNotice(message: locationWarning!),
                    ),
                  if (selectedRoadService != null &&
                      selectedRoadRoute != null &&
                      showVehicles &&
                      liveError != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 76,
                      child: Material(
                        color: Colors.red.shade700,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            liveError!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  if (selectedRoadService != null &&
                      selectedRoadRoute != null &&
                      showVehicles &&
                      !refreshingVehicles &&
                      liveError == null &&
                      filteredVehicles.isEmpty)
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 76,
                      child: Material(
                        color: const Color(0xFF334155),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            'No live buses are currently reported for '
                                '${selectedRoadService!.label} Route '
                                '${selectedRoadRoute!.displayName}. '
                                'Its stops are still shown using the static '
                                'GTFS dataset.',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _MessageCard({
    required this.icon,
    required this.color,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: .22)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(color: _ink, height: 1.4)),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 8),
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _MapNotice extends StatelessWidget {
  final String message;
  const _MapNotice({required this.message});

  @override
  Widget build(BuildContext context) => Material(
    elevation: 2,
    color: const Color(0xFFFFFBEB),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.location_off_outlined, color: Colors.orange),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$message The map is showing the Klang Valley overview.',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, height: 1.35),
            ),
          ),
        ],
      ),
    ),
  );
}

class StationDetailScreen extends StatelessWidget {
  final Station station;
  const StationDetailScreen({super.key, required this.station});
  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      backgroundColor: _page,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        toolbarHeight: 116,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              station.name,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: station.lines.map(LineBadge.new).toList(),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.tonalIcon(
              onPressed: station.latitude == 0
                  ? null
                  : () async {
                try {
                  await openGoogleMaps(station);
                } catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(error.toString())),
                  );
                }
              },
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('Navigate'),
            ),
          ),
        ],
        bottom: const TabBar(
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
          tabs: [
            Tab(text: 'Information'),
            Tab(text: 'Timetable'),
            Tab(text: 'Facilities'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          _InformationTab(station: station),
          _TimetableTab(station: station),
          _FacilitiesTab(station: station),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: station.latitude == 0
                ? null
                : () async {
              try {
                await openGoogleMaps(station);
              } catch (error) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text(error.toString())));
              }
            },
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Open in Google Maps'),
            style: ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size.fromHeight(54)),
              backgroundColor: WidgetStatePropertyAll(_blue),
              foregroundColor: WidgetStatePropertyAll(Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}

class _InformationTab extends StatelessWidget {
  final Station station;
  const _InformationTab({required this.station});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      FutureBuilder<String?>(
        future: AddressService.resolve(station),
        builder: (context, snapshot) => _InfoCard(
          Icons.location_on_outlined,
          'Nearby address',
          snapshot.connectionState == ConnectionState.waiting
              ? 'Finding address...'
              : snapshot.data ?? 'Address is not available in this dataset',
          const Color(0xFFEF4444),
          detail: station.latitude == 0
              ? null
              : '${station.latitude.toStringAsFixed(6)}, '
              '${station.longitude.toStringAsFixed(6)}',
        ),
      ),
      _InfoCard(
        Icons.flag_outlined,
        'Transport Type',
        station.type,
        const Color(0xFF7C3AED),
      ),
      _InfoCard(
        Icons.train_outlined,
        'Lines',
        station.lines.join(', '),
        const Color(0xFF2563EB),
      ),
      _InfoCard(
        Icons.storage_outlined,
        'Data source',
        station.sources
            .map((source) => 'data.gov.my GTFS ${source.replaceAll('_', ' ')}')
            .join('\n'),
        const Color(0xFF475569),
      ),
      const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Text(
          'Address is resolved from OpenStreetMap only when this page is '
              'opened. Coordinates remain the navigation destination.',
          style: TextStyle(color: Color(0xFF64748B), height: 1.4),
        ),
      ),
    ],
  );
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final String? detail;
  const _InfoCard(this.icon, this.label, this.value, this.color, {this.detail});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    elevation: 1,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SoftIcon(icon, color),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value, style: const TextStyle(color: _ink, fontSize: 16)),
                if (detail != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    detail!,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _TimetableTab extends StatelessWidget {
  final Station station;
  const _TimetableTab({required this.station});

  @override
  Widget build(BuildContext context) => FutureBuilder<ScheduleResult>(
    future: StaticScheduleService.loadDepartures(station),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Could not load the supplied GTFS timetable: ${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      final result =
          snapshot.data ?? const ScheduleResult(groups: [], notices: []);
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Row(
            children: [
              Expanded(
                child: Text(
                  'NEXT PUBLISHED DEPARTURES',
                  style: TextStyle(
                    color: Color(0xFF71839E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Chip(
                avatar: Icon(Icons.calendar_today_outlined, size: 16),
                label: Text('Today'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...result.notices.map(
                (notice) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MessageCard(
                icon: Icons.update_outlined,
                color: Colors.orange,
                message: notice,
              ),
            ),
          ),
          if (result.groups.isEmpty)
            const _MessageCard(
              icon: Icons.event_busy_outlined,
              color: Color(0xFF64748B),
              message:
              'No upcoming timetable is available for this stop '
                  'today. This can mean the feed has expired, the stop has no '
                  'scheduled service today, or the operator did not publish '
                  'stop times for it.',
            )
          else
            ...result.groups.map((group) => _DepartureCard(group: group)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, color: _blue),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Times marked “Est.” are calculated from the official '
                        'GTFS frequency windows. They are scheduled estimates, '
                        'not live arrival predictions. The government realtime '
                        'feed currently supplies vehicle positions only.',
                    style: TextStyle(color: _blue, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _DepartureCard extends StatelessWidget {
  final DepartureGroup group;
  const _DepartureCard({required this.group});

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 48),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              group.route,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.destination,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (group.frequencyNotes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ...group.frequencyNotes
                      .take(3)
                      .map(
                        (note) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.schedule_outlined,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              note,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: group.times.map((time) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        time,
                        style: const TextStyle(
                          color: _blue,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _FacilitiesTab extends StatelessWidget {
  final Station station;
  const _FacilitiesTab({required this.station});
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text(
        'AVAILABLE',
        style: TextStyle(color: Color(0xFF71839E), fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: station.accessible == null
              ? const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No verified facility data',
                style: TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This GTFS stop does not include facility fields. '
                    'Parking, lift, escalator and toilet availability are '
                    'shown as unknown instead of being guessed.',
                style: TextStyle(color: Color(0xFF64748B), height: 1.4),
              ),
            ],
          )
              : ListTile(
            contentPadding: EdgeInsets.zero,
            leading: _SoftIcon(
              station.accessible! ? Icons.accessible : Icons.help_outline,
              station.accessible!
                  ? const Color(0xFF059669)
                  : Colors.orange,
            ),
            title: Text(
              station.accessible!
                  ? 'OKU accessible'
                  : 'Not marked as OKU accessible',
              style: const TextStyle(
                color: _ink,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              station.accessible!
                  ? 'Verified by the supplied rail station dataset'
                  : 'Unknown status; it does not prove that access is unavailable',
            ),
          ),
        ),
      ),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFDBEAFE)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, color: _blue),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Facility availability is subject to change. Contact station management for the most current information.',
                style: TextStyle(color: _blue, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}
