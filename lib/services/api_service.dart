import 'dart:math' show cos, sqrt, asin;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// =========================================================
// YOUR CODE (Module 1 / Journey Planning)
// =========================================================
// Upgraded StationModel to support GTFS GPS clustering and multiple IDs
// (Does not affect Module 3 as it relies on RidershipRecord)
class StationModel {
  final List<String> ids;
  final String name;
  final Set<String> lines;
  String category;
  final double lat;
  final double lon;

  StationModel({
    required this.ids, required this.name, required this.lines,
    required this.category, required this.lat, required this.lon,
  });
}

// =========================================================
// FRIEND'S CODE (Module 3 / Crowd AI / Ridership)
// =========================================================
// One row of the ridership CSV: date, origin station, destination station,
// number of trips recorded for that origin-destination pair on that date.
class RidershipRecord {
  final DateTime date;
  final String origin;
  final String destination;
  final int ridership;

  RidershipRecord({
    required this.date,
    required this.origin,
    required this.destination,
    required this.ridership,
  });
}

// =========================================================
// API SERVICE CLASS
// =========================================================
class ApiService {
  // --- FRIEND'S VARIABLES ---
  List<RidershipRecord>? _cache;

  // --- YOUR VARIABLES (Module 1) ---
  List<StationModel> _cachedStations = [];

  // =========================================================
  // YOUR METHODS (Module 1 / Journey Planning)
  // =========================================================

  /// Cleans up raw GTFS station names for UI presentation and clustering
  String _cleanStationName(String rawName) {
    String name = rawName.trim().toUpperCase();
    name = name.replaceAll(RegExp(r'^[A-Za-z]{1,4}\d+\s*[-–]?\s*'), '');
    name = name.replaceAll(RegExp(r'^\([^)]+\)\s*'), '');
    name = name.replaceAll(RegExp(r'\s*\([^)]+\)'), '');
    name = name.replaceAll(RegExp(r'\b(STESEN|STATION|BUS TERMINAL|HUB|HENTIAN)\b', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'\b(MRT|LRT|MONORAIL|KTM|BRT)\b', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'\bCONDOMINIUM\b', caseSensitive: false), 'CONDO');
    name = name.replaceAll('/', ' ');
    name = name.replaceAll('-', ' ');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) return rawName.trim().toUpperCase();
    return name;
  }

  /// Normalizes different GTFS names to standard KL Interchange names
  String _normalizeToMasterInterchange(String cleanName) {
    final map = {
      'MUZIUM NEGARA': 'KL SENTRAL',
      'KUALA LUMPUR': 'PASAR SENI',
      'MERDEKA': 'PLAZA RAKYAT',
      'TBS': 'BANDAR TASIK SELATAN',
      'TERMINAL BERSEPADU SELATAN': 'BANDAR TASIK SELATAN',
      'TRX': 'TUN RAZAK EXCHANGE',
      'BUKIT BINTANG MRT': 'BUKIT BINTANG',
      'BUKIT BINTANG MONORAIL': 'BUKIT BINTANG',
    };
    return map[cleanName] ?? cleanName;
  }

  /// Haversine formula to calculate real-world distance between GPS points
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var a = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  /// Loads all stations from local GTFS assets, infers lines, and clusters nearby stops
  Future<List<StationModel>> loadAllStations() async {
    final Map<String, StationModel> stationMap = {};
    final filePaths = ['assets/gtfs/rail/stops.txt', 'assets/gtfs/mrt_feeder/stops.txt', 'assets/gtfs/bus/stops.txt'];

    for (String path in filePaths) {
      try {
        final String rawFile = await rootBundle.loadString(path);
        final String safeRaw = rawFile.replaceAll('\r\n', '\n');

        List<List<dynamic>> csvTable = const CsvToListConverter(eol: '\n').convert(safeRaw);
        if (csvTable.isEmpty) continue;

        final header = csvTable[0].map((e) => e.toString().trim().toLowerCase()).toList();

        int idIndex = header.indexOf('stop_id'); if (idIndex == -1) idIndex = 0;
        int nameIndex = header.indexOf('stop_name'); if (nameIndex == -1) nameIndex = 1;
        int latIndex = header.indexOf('stop_lat'); if (latIndex == -1) latIndex = 2;
        int lonIndex = header.indexOf('stop_lon'); if (lonIndex == -1) lonIndex = 3;
        int parentIndex = header.indexOf('parent_station');

        String folder = path.contains('rail') ? 'rail' : (path.contains('mrt_feeder') ? 'mrt_feeder' : 'bus');
        String category = path.contains('rail') ? 'Rail' : (path.contains('mrt_feeder') ? 'MRT Feeder' : 'Bus');

        for (int i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.length > nameIndex) {
            final rawStopId = row[idIndex].toString().trim();
            if (rawStopId.isEmpty) continue;

            final stopId = '${folder}_$rawStopId';
            final stopNameClean = _cleanStationName(row[nameIndex].toString().trim());
            final stopName = _normalizeToMasterInterchange(stopNameClean);

            String? parentId;
            if (parentIndex != -1 && row.length > parentIndex && row[parentIndex].toString().trim().isNotEmpty) {
              parentId = '${folder}_${row[parentIndex].toString().trim()}';
            }

            double lat = 0.0, lon = 0.0;
            if (latIndex != -1 && row.length > latIndex) lat = double.tryParse(row[latIndex].toString()) ?? 0.0;
            if (lonIndex != -1 && row.length > lonIndex) lon = double.tryParse(row[lonIndex].toString()) ?? 0.0;

            String inferredLine = category;
            if (stopId.contains('_KJ') || rawStopId.startsWith('KJ')) inferredLine = 'Line 5 (Kelana Jaya)';
            else if (stopId.contains('_KG') || rawStopId.startsWith('KG') || rawStopId.startsWith('SBK')) inferredLine = 'Line 9 (Kajang)';
            else if (stopId.contains('_AG') || rawStopId.startsWith('AG')) inferredLine = 'Line 3 (Ampang)';
            else if (stopId.contains('_SP') || rawStopId.startsWith('SP')) inferredLine = 'Line 4 (Sri Petaling)';
            else if (stopId.contains('_MR') || rawStopId.startsWith('MR')) inferredLine = 'Line 8 (Monorail)';
            else if (stopId.contains('_PY') || rawStopId.startsWith('PY') || rawStopId.startsWith('SSP')) inferredLine = 'Line 12 (Putrajaya)';

            String mapKey = stopName;
            int suffix = 1;
            bool merged = false;

            // Cluster stops within 250 meters into a single StationModel
            while (stationMap.containsKey(mapKey)) {
              final existing = stationMap[mapKey]!;
              if (lat != 0.0 && lon != 0.0 && existing.lat != 0.0 && existing.lon != 0.0 &&
                  _calculateDistance(existing.lat, existing.lon, lat, lon) <= 0.25) {
                existing.ids.add(stopId);
                if (parentId != null) existing.ids.add(parentId);
                existing.lines.add(inferredLine);
                if (category == 'Rail' || category == 'MRT Feeder') existing.category = 'Rail';
                merged = true;
                break;
              }
              mapKey = '$stopName ($suffix)';
              suffix++;
            }

            if (!merged) {
              final idsSet = {stopId};
              if (parentId != null) idsSet.add(parentId);
              stationMap[mapKey] = StationModel(
                ids: idsSet.toList(), name: stopName, lines: {inferredLine}, category: category, lat: lat, lon: lon,
              );
            }
          }
        }
      } catch (e) {
        debugPrint('Error loading stops from $path: $e');
      }
    }

    final parsedStations = stationMap.values.toList();
    parsedStations.sort((a, b) => a.name.compareTo(b.name));
    _cachedStations = parsedStations;
    return parsedStations;
  }

  int _timeToMinutes(String t) {
    final p = t.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }

  bool _matchesStation(StationModel station, String stopId) {
    if (station.ids.contains(stopId)) return true;
    final cleanId = stopId.contains('_') ? stopId.split('_').sublist(1).join('_') : stopId;
    for (var id in station.ids) {
      final cleanStationId = id.contains('_') ? id.split('_').sublist(1).join('_') : id;
      if (cleanStationId == cleanId) return true;
    }
    return false;
  }

  /// The Core Moovit-Grade Routing Engine (Direct, 1-Transfer, and 2-Transfer Rail Bridges)
  Future<List<Map<String, dynamic>>> findRoutes(StationModel origin, StationModel destination) async {
    try {
      final List<Map<String, dynamic>> results = [];
      final Set<String> seenSignatures = {};

      final Map<String, List<Map<String, dynamic>>> allTripStopTimes = {};
      final Map<String, Map<String, dynamic>> allRouteMetadata = {};
      final Map<String, StationModel> stopIdToStation = { for (var s in _cachedStations) for (var id in s.ids) id: s };

      for (final folder in ['rail', 'bus', 'mrt_feeder']) {
        try {
          final String rawFile = await rootBundle.loadString('assets/gtfs/$folder/routes.txt');
          allRouteMetadata.addAll(_parseRouteMetadata(rawFile.replaceAll('\r\n', '\n'), folder));

          final String rawTripsFile = await rootBundle.loadString('assets/gtfs/$folder/trips.txt');
          final tripToRoute = _parseTrips(rawTripsFile.replaceAll('\r\n', '\n'), folder);

          final String rawStopTimesFile = await rootBundle.loadString('assets/gtfs/$folder/stop_times.txt');
          allTripStopTimes.addAll(_parseStopTimes(rawStopTimesFile.replaceAll('\r\n', '\n'), tripToRoute, folder));
        } catch (e) {
          debugPrint('GTFS folder $folder load error: $e');
        }
      }

      final nowMinutes = DateTime.now().hour * 60 + DateTime.now().minute;

      int getWaitTime(int tripMins) {
        int w = tripMins - nowMinutes;
        return w < 0 ? w + 1440 : w;
      }

      Map<String, Map<String, dynamic>> bestDirect = {};
      Map<StationModel, Map<String, Map<String, dynamic>>> reachFromOrigin = {};
      Map<StationModel, Map<String, Map<String, dynamic>>> reachToDest = {};

      // Analyze all trips for fastest Direct routes and local connections
      for (final tripId in allTripStopTimes.keys) {
        final stops = allTripStopTimes[tripId]!;
        if (stops.length < 2) continue;

        int oIdx = stops.indexWhere((s) => _matchesStation(origin, s['stop_id']));
        int dIdx = stops.lastIndexWhere((s) => _matchesStation(destination, s['stop_id']));

        if (oIdx != -1 && dIdx != -1 && oIdx < dIdx) {
          String rId = stops[oIdx]['route_id'];
          int oMins = _timeToMinutes(stops[oIdx]['arrival_time']);
          int wait = getWaitTime(oMins);

          if (!bestDirect.containsKey(rId) || wait < bestDirect[rId]!['wait']) {
            int dur = (_timeToMinutes(stops[dIdx]['arrival_time']) - oMins).abs();
            bestDirect[rId] = { 'wait': wait, 'dur': dur == 0 ? 15 : dur, 'depart': stops[oIdx]['arrival_time'] };
          }
        }

        if (oIdx != -1) {
          String rId = stops[oIdx]['route_id'];
          int oMins = _timeToMinutes(stops[oIdx]['arrival_time']);
          int wait = getWaitTime(oMins);

          for (int i = oIdx + 1; i < stops.length; i++) {
            final stm = stopIdToStation[stops[i]['stop_id']];
            if (stm != null) {
              reachFromOrigin.putIfAbsent(stm, () => {});
              if (!reachFromOrigin[stm]!.containsKey(rId) || wait < reachFromOrigin[stm]![rId]!['wait']) {
                int dur = (_timeToMinutes(stops[i]['arrival_time']) - oMins).abs();
                reachFromOrigin[stm]![rId] = {'wait': wait, 'dur': dur == 0 ? 15 : dur, 'depart': stops[oIdx]['arrival_time']};
              }
            }
          }
        }

        if (dIdx != -1) {
          String rId = stops[dIdx]['route_id'];
          for (int i = 0; i < dIdx; i++) {
            final stm = stopIdToStation[stops[i]['stop_id']];
            if (stm != null) {
              reachToDest.putIfAbsent(stm, () => {});
              int dur = (_timeToMinutes(stops[dIdx]['arrival_time']) - _timeToMinutes(stops[i]['arrival_time'])).abs();
              if (!reachToDest[stm]!.containsKey(rId) || (dur == 0 ? 15 : dur) < reachToDest[stm]![rId]!['dur']) {
                reachToDest[stm]![rId] = {'dur': dur == 0 ? 15 : dur};
              }
            }
          }
        }
      }

      // Local Hub Bridging for PV15 (Simulating Physical Walking Network)
      StationModel? wangsaMajuLrt;
      try { wangsaMajuLrt = _cachedStations.firstWhere((s) => s.name.contains('WANGSA MAJU') && s.category == 'Rail'); } catch (_) {}
      if ((origin.name.contains('PV15') || origin.name.contains('COLUMBIA')) && wangsaMajuLrt != null) {
        for (final rId in allRouteMetadata.keys) {
          if (allRouteMetadata[rId]!['short_name'] == '250' || allRouteMetadata[rId]!['short_name'] == 'T250') {
            reachFromOrigin.putIfAbsent(wangsaMajuLrt, () => {});
            reachFromOrigin[wangsaMajuLrt]![rId] = {'wait': 5, 'dur': 12, 'depart': DateFormat('HH:mm').format(DateTime.now().add(const Duration(minutes: 5)))};
          }
        }
      }

      // Populate Direct Results
      for (final rId in bestDirect.keys) {
        final m = allRouteMetadata[rId] ?? {'short_name': rId, 'color': Colors.blue, 'folder': 'bus'};
        final data = bestDirect[rId]!;
        final departStr = (data['depart'] as String).substring(0, 5);

        results.add({
          'id': rId, 'name': m['short_name'], 'duration': '${data['dur']} min',
          'fare': 'RM ${(data['dur'] * 0.15 + 0.80).toStringAsFixed(2)}', 'badge': 'Direct', 'color': m['color'], 'sig': 'DIR_$rId',
          'wait': data['wait'], 'scheduledDepart': departStr,
          'legs': [ { 'mode': m['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m['short_name'], 'duration': '${data['dur']} min', 'icon': m['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m['color'], 'desc': 'Board ${m['short_name']} at ${origin.name} ($departStr)' } ]
        });
      }

      // Populate 1-Transfer Results
      for (final stm in reachFromOrigin.keys) {
        if (reachToDest.containsKey(stm)) {
          for (final r1Id in reachFromOrigin[stm]!.keys) {
            for (final r2Id in reachToDest[stm]!.keys) {
              if (r1Id == r2Id) continue;
              final m1 = allRouteMetadata[r1Id] ?? {'short_name': r1Id, 'color': Colors.red, 'folder': 'bus'};
              final m2 = allRouteMetadata[r2Id] ?? {'short_name': r2Id, 'color': Colors.blue, 'folder': 'rail'};

              int walkMins = (m1['folder'] == 'rail' && m2['folder'] == 'rail') ? 3 : 5;
              final d1 = reachFromOrigin[stm]![r1Id]!['dur'];
              final d2 = reachToDest[stm]![r2Id]!['dur'];
              final wait = reachFromOrigin[stm]![r1Id]!['wait'];
              final departStr = (reachFromOrigin[stm]![r1Id]!['depart'] as String).substring(0, 5);
              final total = d1 + d2 + walkMins;

              results.add({
                'id': 'MIX', 'name': '${m1['short_name']} + ${m2['short_name']} (via ${stm.name})',
                'duration': '$total min', 'fare': 'RM ${(total * 0.15 + 1.20).toStringAsFixed(2)}', 'badge': '1 Transfer', 'color': Colors.orange, 'sig': '1X_${m1['short_name']}_${stm.name}_${m2['short_name']}',
                'wait': wait, 'scheduledDepart': departStr,
                'legs': [
                  { 'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m1['short_name'], 'duration': '$d1 min', 'icon': m1['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m1['color'], 'desc': 'Board ${m1['short_name']} at ${origin.name} ($departStr)' },
                  { 'mode': 'Walk', 'name': 'Interchange', 'duration': '$walkMins min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Transfer at ${stm.name}' },
                  { 'mode': m2['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m2['short_name'], 'duration': '$d2 min', 'icon': m2['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m2['color'], 'desc': 'Board ${m2['short_name']} -> Arrive at ${destination.name}' }
                ]
              });
            }
          }
        }
      }

      // Populate 2-Transfer Results (Rail Bridges Only)
      Map<StationModel, Map<StationModel, Map<String, dynamic>>> railBridges = {};
      for (final tripId in allTripStopTimes.keys) {
        if (!tripId.startsWith('rail_')) continue;
        final stops = allTripStopTimes[tripId]!;
        for (int i = 0; i < stops.length; i++) {
          final stm1 = stopIdToStation[stops[i]['stop_id']];
          if (stm1 == null || !reachFromOrigin.containsKey(stm1)) continue;

          for (int j = i + 1; j < stops.length; j++) {
            final stm2 = stopIdToStation[stops[j]['stop_id']];
            if (stm2 == null || !reachToDest.containsKey(stm2)) continue;

            String rId = stops[i]['route_id'];
            int dur = (_timeToMinutes(stops[j]['arrival_time']) - _timeToMinutes(stops[i]['arrival_time'])).abs();
            if (dur == 0) dur = 10;

            railBridges.putIfAbsent(stm1, () => {});
            if (!railBridges[stm1]!.containsKey(stm2) || dur < railBridges[stm1]![stm2]!['dur']) {
              railBridges[stm1]![stm2] = {'rId': rId, 'dur': dur};
            }
          }
        }
      }

      for (final stm1 in railBridges.keys) {
        for (final stm2 in railBridges[stm1]!.keys) {
          final bridge = railBridges[stm1]![stm2]!;
          for (final r1Id in reachFromOrigin[stm1]!.keys) {
            for (final r3Id in reachToDest[stm2]!.keys) {
              if (r1Id == bridge['rId'] || bridge['rId'] == r3Id || r1Id == r3Id) continue;

              final m1 = allRouteMetadata[r1Id] ?? {'short_name': r1Id, 'color': Colors.red, 'folder': 'bus'};
              final m2 = allRouteMetadata[bridge['rId']] ?? {'short_name': bridge['rId'], 'color': Colors.blue, 'folder': 'rail'};
              final m3 = allRouteMetadata[r3Id] ?? {'short_name': r3Id, 'color': Colors.green, 'folder': 'rail'};

              int walk1 = (m1['folder'] == 'rail') ? 3 : 5;
              int walk2 = (m3['folder'] == 'rail') ? 3 : 5;

              final d1 = reachFromOrigin[stm1]![r1Id]!['dur'];
              final d2 = bridge['dur'];
              final d3 = reachToDest[stm2]![r3Id]!['dur'];
              final wait = reachFromOrigin[stm1]![r1Id]!['wait'];
              final departStr = (reachFromOrigin[stm1]![r1Id]!['depart'] as String).substring(0, 5);

              results.add({
                'id': 'MIX2', 'name': '${m1['short_name']} -> ${m2['short_name']} -> ${m3['short_name']}',
                'duration': '${d1 + d2 + d3 + walk1 + walk2} min', 'fare': 'RM ${((d1 + d2 + d3) * 0.15 + 1.50).toStringAsFixed(2)}', 'badge': '2 Transfers', 'color': Colors.purple,
                'sig': '2X_${m1['short_name']}_${stm1.name}_${m2['short_name']}_${stm2.name}_${m3['short_name']}',
                'wait': wait, 'scheduledDepart': departStr,
                'legs': [
                  { 'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m1['short_name'], 'duration': '$d1 min', 'icon': m1['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m1['color'], 'desc': 'Board at ${origin.name} ($departStr)' },
                  { 'mode': 'Walk', 'name': 'Transfer', 'duration': '$walk1 min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Transfer at ${stm1.name}' },
                  { 'mode': 'Rail', 'name': m2['short_name'], 'duration': '$d2 min', 'icon': Icons.train, 'color': m2['color'], 'desc': 'Connect via ${stm1.name}' },
                  { 'mode': 'Walk', 'name': 'Transfer', 'duration': '$walk2 min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Transfer at ${stm2.name}' },
                  { 'mode': m3['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m3['short_name'], 'duration': '$d3 min', 'icon': m3['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m3['color'], 'desc': 'Arrive at ${destination.name}' }
                ]
              });
            }
          }
        }
      }

      // Cleanup and Deduplication
      final Map<String, Map<String, dynamic>> uniqueResults = {};
      for (var r in results) {
        if (!uniqueResults.containsKey(r['sig']) ||
            int.parse(r['duration'].split(' ')[0]) < int.parse(uniqueResults[r['sig']]!['duration'].split(' ')[0])) {
          uniqueResults[r['sig']] = r;
        }
      }

      final finalResults = uniqueResults.values.toList();

      // Advanced Time & Mode Sorting
      finalResults.sort((a, b) {
        int da = int.parse(a['duration'].split(' ')[0]);
        int db = int.parse(b['duration'].split(' ')[0]);

        int waitA = a['wait'] ?? 30;
        int waitB = b['wait'] ?? 30;

        int scoreA = da + waitA;
        int scoreB = db + waitB;

        if (a['badge'] == 'Direct') scoreA -= 2000;
        if (b['badge'] == 'Direct') scoreB -= 2000;

        bool aEndsWithBus = a['legs'].last['mode'] == 'Bus';
        bool bEndsWithBus = b['legs'].last['mode'] == 'Bus';

        if (a['badge'] != 'Direct') {
          if (aEndsWithBus) scoreA += 50;
          if (!a['legs'].any((l) => l['mode'] == 'Rail')) scoreA += 100;
        }
        if (b['badge'] != 'Direct') {
          if (bEndsWithBus) scoreB += 50;
          if (!b['legs'].any((l) => l['mode'] == 'Rail')) scoreB += 100;
        }

        return scoreA.compareTo(scoreB);
      });

      return finalResults.take(4).toList();
    } catch (e) {
      debugPrint('Error finding routes: $e');
      return [];
    }
  }

  /// Parses routes.txt for Line Names and Hex Colors
  Map<String, Map<String, dynamic>> _parseRouteMetadata(String raw, String folder) {
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final Map<String, Map<String, dynamic>> metadata = {};
    if (lines.isEmpty) return metadata;

    final header = lines[0].split(',').map((e) => e.trim().replaceAll('"', '')).toList();
    final idIdx = header.indexOf('route_id');
    final shortNameIdx = header.indexOf('route_short_name');
    final colorIdx = header.indexOf('route_color');

    for (final line in lines.skip(1)) {
      final parts = line.split(',').map((e) => e.trim().replaceAll('"', '')).toList();
      if (parts.length <= shortNameIdx || idIdx == -1 || idIdx >= parts.length) continue;
      final routeId = '${folder}_${parts[idIdx]}';
      String routeColorHex = colorIdx != -1 && parts.length > colorIdx ? parts[colorIdx] : '';
      if (routeColorHex.length != 6) routeColorHex = folder == 'rail' ? '2563EB' : 'DC2626';

      metadata[routeId] = {
        'short_name': parts[shortNameIdx],
        'color': Color(int.parse('0xFF$routeColorHex')),
        'folder': folder
      };
    }
    return metadata;
  }

  /// Parses trips.txt mapping Trip ID to Route ID
  Map<String, String> _parseTrips(String raw, String folder) {
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final Map<String, String> tripToRoute = {};
    if (lines.isEmpty) return tripToRoute;
    final header = lines[0].split(',').map((e) => e.trim().replaceAll('"', '')).toList();
    final routeIdIdx = header.indexOf('route_id');
    final tripIdIdx = header.indexOf('trip_id');
    if (routeIdIdx == -1 || tripIdIdx == -1) return tripToRoute;

    for (final line in lines.skip(1)) {
      final parts = line.split(',').map((e) => e.trim().replaceAll('"', '')).toList();
      if (parts.length > tripIdIdx && parts.length > routeIdIdx) {
        tripToRoute['${folder}_${parts[tripIdIdx]}'] = '${folder}_${parts[routeIdIdx]}';
      }
    }
    return tripToRoute;
  }

  /// Parses stop_times.txt mapping Trip ID to its sequential Stop IDs
  Map<String, List<Map<String, dynamic>>> _parseStopTimes(String raw, Map<String, String> tripToRoute, String folder) {
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final Map<String, List<Map<String, dynamic>>> tripStopTimes = {};
    if (lines.isEmpty) return tripStopTimes;

    final header = lines[0].split(',').map((e) => e.trim().replaceAll('"', '')).toList();
    final tripIdIdx = header.indexOf('trip_id');
    final stopIdIdx = header.indexOf('stop_id');
    final arrivalTimeIdx = header.indexOf('arrival_time');
    final seqIdx = header.indexOf('stop_sequence');

    if (tripIdIdx == -1 || stopIdIdx == -1 || arrivalTimeIdx == -1) return tripStopTimes;

    for (final line in lines.skip(1)) {
      final parts = line.split(',').map((e) => e.trim().replaceAll('"', '')).toList();
      if (parts.length > stopIdIdx && parts.length > arrivalTimeIdx && parts.length > tripIdIdx) {
        final tripId = '${folder}_${parts[tripIdIdx]}';
        final seq = seqIdx != -1 && parts.length > seqIdx ? int.tryParse(parts[seqIdx]) ?? 0 : 0;

        if (!tripStopTimes.containsKey(tripId)) tripStopTimes[tripId] = [];

        tripStopTimes[tripId]!.add({
          'stop_id': '${folder}_${parts[stopIdIdx]}',
          'arrival_time': parts[arrivalTimeIdx],
          'route_id': tripToRoute[tripId] ?? tripId,
          'seq': seq,
        });
      }
    }

    for (final tripId in tripStopTimes.keys) {
      tripStopTimes[tripId]!.sort((a, b) => (a['seq'] as int).compareTo(b['seq'] as int));
    }

    return tripStopTimes;
  }

  Duration _parseDuration(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 3) return Duration.zero;
    return Duration(hours: int.tryParse(parts[0]) ?? 0, minutes: int.tryParse(parts[1]) ?? 0, seconds: int.tryParse(parts[2]) ?? 0);
  }

  /// Saves the final computed journey out to Supabase for the Recent Journeys list
  Future<void> saveNavigationHistory({
    required String origin,
    required String destination,
    required double fare,
    required int durationMinutes,
    required String departureTime,
    required String estimatedArrivalTime,
    required List<Map<String, dynamic>> transitSteps,
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User is not logged in. Please log in first.');

      await Supabase.instance.client.from('navigation_history').insert({
        'user_id': user.id,
        'origin': origin,
        'destination': destination,
        'fare': fare,
        'currency': 'MYR',
        'duration_minutes': durationMinutes,
        'departure_time': departureTime,
        'estimated_arrival_time': estimatedArrivalTime,
        'transit_steps': transitSteps,
        'status': 'in_progress',
      });
    } catch (e) {
      throw Exception('Failed to save navigation to database: ${e.toString()}');
    }
  }


  // =========================================================
  // FRIEND'S CODE (Module 3 / Crowd AI / Ridership)
  // =========================================================

  // Parses assets/ridership.csv into a list of RidershipRecord.
  // Cached after the first successful load so we don't re-read the file
  // every time a screen asks for data.
  Future<List<RidershipRecord>> loadRidership() async {
    if (_cache != null) return _cache!;

    final String raw = await rootBundle.loadString('assets/ridership.csv');
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();

    // First line is the header. IMPORTANT: the real government CSV's column
    // order is "origin,destination,date,ridership" — NOT
    // "date,origin,destination,ridership". Parsing it in the wrong order
    // means DateTime.parse() gets a station name instead of a date, throws,
    // and every row is silently skipped by the catch block below. Fixed here.
    final records = <RidershipRecord>[];
    for (final line in lines.skip(1)) {
      final parts = line.split(',');
      if (parts.length < 4) continue; // skips malformed/truncated rows (e.g. a cut-off last line)
      try {
        records.add(RidershipRecord(
          origin: parts[0].trim(),
          destination: parts[1].trim(),
          date: DateTime.parse(parts[2].trim()),
          ridership: double.parse(parts[3].trim()).round(),
        ));
      } catch (_) {
        // Skip any row that fails to parse (bad date/number) rather than
        // crashing the whole screen.
        continue;
      }
    }

    _cache = records;
    return records;
  }

  // The dataset's marker row for "total across all origins/destinations".
  static const String kAllStationsCode = 'A0: All Stations';

  // ---------------------------------------------------------------------
  // A0 "All Stations" rows = real total daily ridership recorded AT a
  // station (across every origin). Used for Crowd Estimate / Peak Hours /
  // History. NOTE: this intentionally does NOT also match rows where the
  // station appears as an O-D origin or destination — mixing those in
  // would double-count trips (the station's real daily total already
  // includes them). O-D-specific rows are handled separately below.
  // ---------------------------------------------------------------------

  // All distinct stations that have an "A0: All Stations" total record —
  // i.e. every real station in the dataset.
  Future<List<String>> getStationList() async {
    final all = await loadRidership();
    final names = all
        .where((r) => r.origin == kAllStationsCode)
        .map((r) => r.destination)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  // A station's real total-ridership records, sorted chronologically.
  Future<List<RidershipRecord>> getStationTotalRecords(String station) async {
    final all = await loadRidership();
    return all
        .where((r) => r.origin == kAllStationsCode && r.destination == station)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // Groups a station's total records by date. With this dataset there's
  // already exactly one A0 row per day, but grouping+summing keeps this
  // correct even if a fuller dataset later has more than one.
  Future<List<MapEntry<DateTime, int>>> getDailyTotalsForStation(
      String station) async {
    final records = await getStationTotalRecords(station);
    final Map<DateTime, int> totals = {};
    for (final r in records) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      totals[day] = (totals[day] ?? 0) + r.ridership;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  // Real average daily ridership for a station, computed from the actual
  // dataset. Used to scale the rule-based crowd prediction so busier real
  // stations genuinely produce higher estimates than quieter ones.
  Future<double> getStationAverageRidership(String station) async {
    final daily = await getDailyTotalsForStation(station);
    if (daily.isEmpty) return 0;
    final total = daily.fold<int>(0, (sum, e) => sum + e.value);
    return total / daily.length;
  }

  // Real historical average ridership for a station on one specific
  // weekday (1 = Monday ... 7 = Sunday, Dart's DateTime.weekday convention).
  // This is what drives the crowd-prediction magnitude with real data.
  Future<double> getStationAverageForWeekday(String station, int weekday) async {
    final daily = await getDailyTotalsForStation(station);
    final matching = daily.where((e) => e.key.weekday == weekday).toList();
    if (matching.isEmpty) return getStationAverageRidership(station);
    final total = matching.fold<int>(0, (sum, e) => sum + e.value);
    return total / matching.length;
  }

  // Network-wide average daily ridership across all stations/days — used
  // as a neutral baseline so a station's magnitude can be expressed as
  // "busier/quieter than the network average" rather than an absolute
  // number that's hard to interpret in isolation.
  Future<double> getNetworkAverageRidership() async {
    final all = await loadRidership();
    final totals = all.where((r) => r.origin == kAllStationsCode).toList();
    if (totals.isEmpty) return 1;
    final sum = totals.fold<int>(0, (s, r) => s + r.ridership);
    return sum / totals.length;
  }

  // ---------------------------------------------------------------------
  // Origin-Destination (O-D) ridership insights — REAL station-to-station
  // trip data. Deliberately kept to simple filter/group/sum/sort logic:
  // no path-finding, no multi-hop routes, no fare/ETA — that's Module 1's
  // job. This only answers "how many people travelled between two named
  // stations", never "how do I get from A to B".
  // ---------------------------------------------------------------------

  // Every station that has at least one real outgoing O-D record — lets
  // the UI tell the user upfront which stations currently have connection
  // data, instead of silently showing an empty result.
  Future<List<String>> getStationsWithOutgoingData() async {
    final all = await loadRidership();
    final origins = all
        .where((r) => r.origin != kAllStationsCode && r.destination != kAllStationsCode)
        .map((r) => r.origin)
        .toSet()
        .toList();
    origins.sort();
    return origins;
  }

  // Top [limit] destinations reached from [station], by total real trips
  // summed across every date on file. Pure group-by + sum + sort.
  Future<List<MapEntry<String, int>>> getTopDestinationsFrom(
      String station, {int limit = 5}) async {
    final all = await loadRidership();
    final Map<String, int> totals = {};
    for (final r in all) {
      if (r.origin == station && r.destination != kAllStationsCode) {
        totals[r.destination] = (totals[r.destination] ?? 0) + r.ridership;
      }
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  // Top [limit] origins that trips into [station] came from, by total
  // real trips summed across every date on file.
  Future<List<MapEntry<String, int>>> getTopOriginsInto(
      String station, {int limit = 5}) async {
    final all = await loadRidership();
    final Map<String, int> totals = {};
    for (final r in all) {
      if (r.destination == station && r.origin != kAllStationsCode) {
        totals[r.origin] = (totals[r.origin] ?? 0) + r.ridership;
      }
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  // Total real outgoing trips recorded from [station] (sum across all
  // real destinations and dates — excludes the A0 marker rows).
  Future<int> getTotalOutgoing(String station) async {
    final all = await loadRidership();
    return all
        .where((r) => r.origin == station && r.destination != kAllStationsCode)
        .fold<int>(0, (s, r) => s + r.ridership);
  }

  // Total real incoming trips recorded into [station].
  Future<int> getTotalIncoming(String station) async {
    final all = await loadRidership();
    return all
        .where((r) => r.destination == station && r.origin != kAllStationsCode)
        .fold<int>(0, (s, r) => s + r.ridership);
  }

  // Network-wide leaderboard: the busiest [limit] station-to-station
  // connections by total real trips, regardless of which station the user
  // is looking at. Group by (origin, destination) pair, sum, sort desc.
  Future<List<MapEntry<String, int>>> getBusiestConnections({int limit = 10}) async {
    final all = await loadRidership();
    final Map<String, int> totals = {};
    for (final r in all) {
      if (r.origin == kAllStationsCode || r.destination == kAllStationsCode) continue;
      final key = '${r.origin} → ${r.destination}';
      totals[key] = (totals[key] ?? 0) + r.ridership;
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  // Simple status line shown at the top of the AI Crowd screen so users
  // can see the dataset actually loaded, instead of a fake "syncing" text.
  Future<String> getDatasetStatus() async {
    try {
      final records = await loadRidership();
      if (records.isEmpty) {
        return 'No ridership records found in local dataset.';
      }
      return 'Local dataset loaded: ${records.length} ridership records';
    } catch (e) {
      return 'Could not load local ridership dataset.';
    }
  }

  // Kept for Module 2 (real-time bus position) — not used by Module 3.
  Future<String> getRealtimeBusPositions() async {
    try {
      final response = await http.get(Uri.parse(
          'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl'));
      if (response.statusCode == 200) {
        return 'Connected: Received ${response.bodyBytes.length} bytes of live data';
      }
      return 'Failed to load live data';
    } catch (e) {
      return 'API Connection Error';
    }
  }
}