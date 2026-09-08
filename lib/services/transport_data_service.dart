part of '../screens/transport_data.dart';

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
  final List<LatLng> shapePoints;

  const TransitRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.stopIds,
    required this.shapePoints,
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
    final fallbackShapeByRoute = <String, String>{};
    final preferredShapeByRoute = <String, String>{};
    if (tripRows.isNotEmpty) {
      final header = _csvRow(tripRows.first);
      final tripIndex = header.indexOf('trip_id');
      final routeIndex = header.indexOf('route_id');
      final shapeIndex = header.indexOf('shape_id');
      final directionIndex = header.indexOf('direction_id');
      final required = math.max(tripIndex, routeIndex);
      for (final row in tripRows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (required < 0 || values.length <= required) continue;
        final routeId = values[routeIndex].trim();
        routeByTrip[values[tripIndex].trim()] = routeId;
        if (shapeIndex < 0 || values.length <= shapeIndex) continue;
        final shapeId = values[shapeIndex].trim();
        if (routeId.isEmpty || shapeId.isEmpty) continue;
        fallbackShapeByRoute.putIfAbsent(routeId, () => shapeId);
        final isFirstDirection =
            directionIndex < 0 ||
                values.length <= directionIndex ||
                values[directionIndex].trim() == '0';
        if (isFirstDirection) {
          preferredShapeByRoute.putIfAbsent(routeId, () => shapeId);
        }
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

    final selectedShapeByRoute = <String, String>{
      for (final routeId in routeDetails.keys)
        if (preferredShapeByRoute[routeId] ?? fallbackShapeByRoute[routeId]
        case final String shapeId)
          routeId: shapeId,
    };
    final shapePointsByRoute = await _loadSelectedShapes(
      base,
      selectedShapeByRoute,
    );

    final routes =
    routeDetails.entries
        .where((entry) => stopsByRoute[entry.key]?.isNotEmpty == true)
        .map(
          (entry) => TransitRoute(
        id: entry.key,
        shortName: entry.value.$1,
        longName: entry.value.$2,
        stopIds: stopsByRoute[entry.key]!,
        shapePoints: shapePointsByRoute[entry.key] ?? const [],
      ),
    )
        .toList()
      ..sort((a, b) => _compareRouteNames(a.displayName, b.displayName));
    _cache[base] = routes;
    return routes;
  }

  static Future<Map<String, List<LatLng>>> _loadSelectedShapes(
      String base,
      Map<String, String> selectedShapeByRoute,
      ) async {
    if (selectedShapeByRoute.isEmpty) return const {};
    try {
      final rows = (await rootBundle.loadString(
        '$base/shapes.txt',
      )).split(RegExp(r'\r?\n'));
      if (rows.isEmpty) return const {};

      final header = _csvRow(rows.first);
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
      if (required < 0) return const {};

      final selectedIds = selectedShapeByRoute.values.toSet();
      final pointsByShape = <String, List<(int, LatLng)>>{};
      for (final row in rows.skip(1)) {
        if (row.trim().isEmpty) continue;
        final values = _csvRow(row);
        if (values.length <= required) continue;
        final shapeId = values[idIndex].trim();
        if (!selectedIds.contains(shapeId)) continue;
        final latitude = double.tryParse(values[latitudeIndex].trim());
        final longitude = double.tryParse(values[longitudeIndex].trim());
        final sequence = int.tryParse(values[sequenceIndex].trim());
        if (latitude == null || longitude == null || sequence == null) continue;
        pointsByShape.putIfAbsent(shapeId, () => []).add((
        sequence,
        LatLng(latitude, longitude),
        ));
      }

      final result = <String, List<LatLng>>{};
      for (final entry in selectedShapeByRoute.entries) {
        final points = pointsByShape[entry.value];
        if (points == null || points.isEmpty) continue;
        points.sort((a, b) => a.$1.compareTo(b.$1));
        result[entry.key] = points.map((point) => point.$2).toList();
      }
      return result;
    } catch (_) {

      return const {};
    }
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
          color: colorsByRoute[routeId] ?? lineColor(routeId),
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
  static Future<ScheduleResult> loadDepartures(
    Station station, {
    DateTime? date,
    int? startSeconds,
    int? endSeconds,
  }) async {
    if (station.stopIds.isEmpty || station.sources.isEmpty) {
      return const ScheduleResult(groups: [], notices: []);
    }

    final now = DateTime.now();
    final serviceDate = date == null
        ? DateTime(now.year, now.month, now.day)
        : DateTime(date.year, date.month, date.day);
    final groups = <String, _DepartureAccumulator>{};
    final notices = <String>[];
    final windowStart =
        startSeconds ?? scheduleCutoffSeconds(serviceDate, now);
    final windowEnd = endSeconds;

    for (final source in station.sources) {
      final base = 'assets/gtfs/$source';
      final calendar = await _activeServices(base, serviceDate);
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
        final routeLabel = route?.shortName.trim().isNotEmpty == true
            ? route!.shortName.trim()
            : route?.longName.trim().isNotEmpty == true
            ? route!.longName.trim()
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
          if (isInsideScheduleWindow(
            scheduledSeconds,
            startSeconds: windowStart,
            endSeconds: windowEnd,
          )) {
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
          if (stationEnd <= windowStart ||
              (windowEnd != null && stationStart >= windowEnd)) {
            continue;
          }

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
            if (departure < windowStart) continue;
            if (windowEnd != null && departure >= windowEnd) break;
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

int scheduleCutoffSeconds(DateTime selectedDate, DateTime now) {
  final isToday = selectedDate.year == now.year &&
      selectedDate.month == now.month &&
      selectedDate.day == now.day;
  return isToday ? now.hour * 3600 + now.minute * 60 + now.second : 0;
}

bool isInsideScheduleWindow(
  int seconds, {
  required int startSeconds,
  int? endSeconds,
}) {
  return seconds >= startSeconds &&
      (endSeconds == null || seconds < endSeconds);
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
  static const String _table = 'recent_station_searches';

  static String get _storageKey {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    return userId == null
        ? 'transport_recent_stations_guest_v1'
        : 'transport_recent_stations_user_${userId}_v1';
  }

  static Future<List<Station>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final localKeys = preferences.getStringList(_storageKey) ?? const <String>[];
    var keys = localKeys;

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final rows = await Supabase.instance.client
            .from(_table)
            .select('station_key')
            .eq('user_id', user.id)
            .order('searched_at', ascending: false)
            .limit(maximumItems);
        final cloudKeys = rows
            .map((row) => row['station_key']?.toString())
            .whereType<String>()
            .where((key) => key.isNotEmpty)
            .toList();

        if (cloudKeys.isEmpty && localKeys.isNotEmpty) {
          await _uploadExistingHistory(user.id, localKeys);
          keys = localKeys.take(maximumItems).toList();
        } else {
          keys = cloudKeys;
          await preferences.setStringList(_storageKey, keys);
        }
      } catch (_) {

        keys = localKeys;
      }
    }

    if (keys.isEmpty) return [];

    final stations = await StationRepository.instance.loadAll();
    final byKey = {
      for (final station in stations) _stationKey(station): station,
    };
    final byLegacyName = <String, Station>{};
    for (final station in stations) {
      byLegacyName.putIfAbsent(
        station.name.trim().toUpperCase(),
            () => station,
      );
    }
    return keys
        .map((key) => byKey[key] ?? byLegacyName[key])
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

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      final client = Supabase.instance.client;
      await client.from(_table).upsert({
        'user_id': user.id,
        'station_key': key,
        'station_name': station.name,
        'searched_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'user_id,station_key');

      final oldRows = await client
          .from(_table)
          .select('station_key')
          .eq('user_id', user.id)
          .order('searched_at', ascending: false)
          .range(maximumItems, maximumItems + 49);
      for (final row in oldRows) {
        final oldKey = row['station_key']?.toString();
        if (oldKey == null || oldKey.isEmpty) continue;
        await client
            .from(_table)
            .delete()
            .eq('user_id', user.id)
            .eq('station_key', oldKey);
      }
    } catch (_) {

    }
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_storageKey);

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    try {
      await Supabase.instance.client
          .from(_table)
          .delete()
          .eq('user_id', user.id);
    } catch (_) {

    }
  }

  static Future<void> _uploadExistingHistory(
    String userId,
    List<String> keys,
  ) async {
    final stations = await StationRepository.instance.loadAll();
    final byKey = {
      for (final station in stations) _stationKey(station): station,
    };
    final now = DateTime.now().toUtc();
    final rows = <Map<String, Object>>[];
    for (var index = 0; index < keys.length && index < maximumItems; index++) {
      final key = keys[index];
      rows.add({
        'user_id': userId,
        'station_key': key,
        'station_name': byKey[key]?.name ?? key.split('|').first,
        'searched_at': now
            .subtract(Duration(milliseconds: index))
            .toIso8601String(),
      });
    }
    if (rows.isNotEmpty) {
      await Supabase.instance.client
          .from(_table)
          .upsert(rows, onConflict: 'user_id,station_key');
    }
  }

  static String _stationKey(Station station) {
    return '${station.name.trim().toUpperCase()}|'
        '${station.latitude.toStringAsFixed(5)}|'
        '${station.longitude.toStringAsFixed(5)}';
  }
}

Future<void> openStationDetails(BuildContext context, Station station) async {
  try {
    await RecentStationService.add(station);
  } catch (_) {

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

    final grouped = <String, List<Station>>{};
    for (final station in all) {
      final key = station.name.trim().toUpperCase();
      final candidates = grouped.putIfAbsent(key, () => []);
      final matchingIndex = candidates.indexWhere(
            (existing) =>
        existing.latitude != 0 &&
            existing.longitude != 0 &&
            station.latitude != 0 &&
            station.longitude != 0 &&
            distanceKm(
              existing.latitude,
              existing.longitude,
              station.latitude,
              station.longitude,
            ) <=
                .3,
      );
      if (matchingIndex < 0) {
        candidates.add(station);
      } else {
        candidates[matchingIndex] = _mergeStations(
          candidates[matchingIndex],
          station,
        );
      }
    }

    _cache = grouped.values.expand((stations) => stations).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return _cache!;
  }

  Station _mergeStations(Station existing, Station station) {
    return Station(
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
  return switch (line.trim().toUpperCase()) {
    'AG' => const Color(0xFFE57200),
    'KJ' => const Color(0xFFD50032),
    'PH' => const Color(0xFF76232F),
    'KGL' || 'KG' => const Color(0xFF047940),
    'PYL' || 'PY' => const Color(0xFFFFCD00),
    'MR' => const Color(0xFF84BD00),
    'BRT' => const Color(0xFF115740),
    'SA' => const Color(0xFF00A9E0),
    'KT' => const Color(0xFF16A34A),
    'EL' => const Color(0xFF6366F1),
    'BUS' => const Color(0xFF3B82F6),
    'T' => const Color(0xFF06B6D4),
    _ => Colors.blueGrey,
  };
}

Color lineForegroundColor(String line) {
  return switch (line.trim().toUpperCase()) {
    'PYL' || 'PY' || 'MR' => const Color(0xFF1E293B),
    _ => Colors.white,
  };
}

String railLineName(String line) {
  return switch (line.trim().toUpperCase()) {
    'AG' => 'Ampang Line',
    'KJ' => 'Kelana Jaya Line',
    'PH' => 'Sri Petaling Line',
    'KGL' || 'KG' => 'Kajang Line',
    'PYL' || 'PY' => 'Putrajaya Line',
    'MR' => 'KL Monorail Line',
    'BRT' => 'Sunway BRT Line',
    'SA' => 'Shah Alam Line',
    _ => line,
  };
}
