import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

class StationModel {
  final String id;
  final String name;
  final Set<String> lines;
  final String category; // 'rail', 'bus', or 'mrt_feeder'

  StationModel({
    required this.id,
    required this.name,
    required this.lines,
    required this.category,
  });
}

class ApiService {
  // --- GTFS Static Parsing ---

  /// Reads and merges stations across Rail, Bus, and MRT Feeder datasets
  Future<List<StationModel>> loadAllStations() async {
    final List<StationModel> allStations = [];
    final Map<String, StationModel> stationMap = {};

    // 1. Load Rail Stations
    final railStations = await _parseGtfsStops('assets/gtfs/rail/stops.txt', 'rail');
    for (var station in railStations) {
      if (stationMap.containsKey(station.name)) {
        stationMap[station.name]!.lines.addAll(station.lines);
      } else {
        stationMap[station.name] = station;
      }
    }

    // 2. Load MRT Feeder Bus Stations
    final feederStations = await _parseGtfsStops('assets/gtfs/mrt_feeder/stops.txt', 'mrt_feeder');
    for (var station in feederStations) {
      if (stationMap.containsKey(station.name)) {
        stationMap[station.name]!.lines.addAll(station.lines);
      } else {
        stationMap[station.name] = station;
      }
    }

    // 3. Load Bus Stations
    final busStations = await _parseGtfsStops('assets/gtfs/bus/stops.txt', 'bus');
    for (var station in busStations) {
      if (stationMap.containsKey(station.name)) {
        stationMap[station.name]!.lines.addAll(station.lines);
      } else {
        stationMap[station.name] = station;
      }
    }

    allStations.addAll(stationMap.values);
    allStations.sort((a, b) => a.name.compareTo(b.name));
    return allStations;
  }

  Future<List<StationModel>> _parseGtfsStops(String path, String category) async {
    try {
      final String rawData = await rootBundle.loadString(path);
      final List<String> lines = rawData.split('\n');
      if (lines.isEmpty) return [];

      final headers = lines.first.split(',');
      final int idIdx = headers.indexWhere((h) => h.trim() == 'stop_id');
      final int nameIdx = headers.indexWhere((h) => h.trim() == 'stop_name');

      if (idIdx == -1 || nameIdx == -1) return [];

      List<StationModel> stations = [];

      for (int i = 1; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) continue;

        final cols = line.split(',');
        if (cols.length > nameIdx && cols.length > idIdx) {
          final stopId = cols[idIdx].replaceAll('"', '').trim();
          final stopName = cols[nameIdx].replaceAll('"', '').trim();

          // Infer line code badge based on stop ID or station name prefix
          final Set<String> lineBadges = _inferLineBadge(stopId, stopName, category);

          stations.add(StationModel(
            id: stopId,
            name: stopName,
            lines: lineBadges,
            category: category,
          ));
        }
      }
      return stations;
    } catch (e) {
      return [];
    }
  }

  Set<String> _inferLineBadge(String stopId, String stopName, String category) {
    final Set<String> badges = {};
    final upperName = stopName.toUpperCase();
    final upperId = stopId.toUpperCase();

    if (category == 'rail') {
      if (upperId.startsWith('KJ') || upperName.contains('KELANA JAYA')) badges.add('KJ');
      if (upperId.startsWith('PY') || upperName.contains('PUTRAJAYA')) badges.add('PY');
      if (upperId.startsWith('AG') || upperName.contains('AMPANG')) badges.add('AG');
      if (upperId.startsWith('SP') || upperName.contains('SRI PETALING')) badges.add('SP');
      if (upperId.startsWith('MR') || upperName.contains('MONORAIL')) badges.add('MR');
      if (upperId.startsWith('KG') || upperName.contains('KAJANG')) badges.add('KG');
      if (upperId.startsWith('KT') || upperName.contains('KLIA')) badges.add('KT');
      if (badges.isEmpty) badges.add('LRT');
    } else if (category == 'mrt_feeder') {
      badges.add('T');
    } else {
      badges.add('BUS');
    }

    return badges;
  }

  // --- Live GTFS Realtime API (Module 2) ---
  Future<String> fetchLiveVehiclePositions() async {
    try {
      final response = await http.get(Uri.parse(
          'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl'));
      if (response.statusCode == 200) {
        return 'Connected: Received ${response.bodyBytes.length} bytes of live GTFS data';
      }
      return 'Failed to fetch live data (HTTP ${response.statusCode})';
    } catch (e) {
      return 'API Connection Error: $e';
    }
  }
}