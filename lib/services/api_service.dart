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
  // --- FRIEND'S VARIABLES (Module 3) --- Small, targeted caches — never
  // the whole 3.9M-row table, and never the whole 16K-row od_totals view.
  final Map<String, List<RidershipRecord>> _stationRecordsCache = {};
  List<String>? _stationListCache;
  List<String>? _odOriginsCache; // from the tiny od_origins view (~146 rows)
  double? _networkAverageCache;

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

  // ---------------------------------------------------------------------
  // NOTE ON SCALE: the "ridership" table has ~3.9 MILLION rows in
  // Supabase. Pulling the whole table (or the whole od_totals view) into
  // the app is not viable at this size — instead:
  //   - Per-station queries fetch only ~236 rows at a time (one station's
  //     real daily history), not the whole table.
  //   - Small Postgres VIEWS (station_list, od_totals, od_origins,
  //     network_average) do the heavy GROUP BY / SUM / AVG work inside
  //     the database. O-D methods below query od_totals with a targeted
  //     filter + sort + limit rather than loading it wholesale.
  // ---------------------------------------------------------------------

  static const String kAllStationsCode = 'A0: All Stations';

  // Every real station — from the small "station_list" view.
  Future<List<String>> getStationList() async {
    if (_stationListCache != null) return _stationListCache!;
    final response = await Supabase.instance.client
        .from('station_list')
        .select('station')
        .order('station');
    final names = response.map((row) => row['station'] as String).toList();
    _stationListCache = names;
    return names;
  }

  // A single station's real daily total-ridership records — a targeted
  // query (~236 rows max), sorted chronologically, cached per station.
  Future<List<RidershipRecord>> getStationTotalRecords(String station) async {
    if (_stationRecordsCache.containsKey(station)) {
      return _stationRecordsCache[station]!;
    }
    final response = await Supabase.instance.client
        .from('ridership')
        .select('origin, destination, date, ridership')
        .eq('origin', kAllStationsCode)
        .eq('destination', station)
        .order('date');

    final records = <RidershipRecord>[];
    for (final row in response) {
      try {
        records.add(RidershipRecord(
          origin: row['origin'] as String,
          destination: row['destination'] as String,
          date: DateTime.parse(row['date'] as String),
          ridership: (row['ridership'] as num).round(),
        ));
      } catch (_) {
        continue; // skip any row that fails to parse
      }
    }
    _stationRecordsCache[station] = records;
    return records;
  }

  Future<List<MapEntry<DateTime, int>>> getDailyTotalsForStation(String station) async {
    final records = await getStationTotalRecords(station);
    return records.map((r) => MapEntry(r.date, r.ridership)).toList();
  }

  // Real average daily ridership for a station.
  Future<double> getStationAverageRidership(String station) async {
    final records = await getStationTotalRecords(station);
    if (records.isEmpty) return 0;
    final total = records.fold<int>(0, (sum, r) => sum + r.ridership);
    return total / records.length;
  }

  // Real historical average ridership for a station on one specific
  // weekday (1 = Monday ... 7 = Sunday). Drives the crowd-prediction
  // magnitude with real data.
  Future<double> getStationAverageForWeekday(String station, int weekday) async {
    final records = await getStationTotalRecords(station);
    final matching = records.where((r) => r.date.weekday == weekday).toList();
    if (matching.isEmpty) return getStationAverageRidership(station);
    final total = matching.fold<int>(0, (sum, r) => sum + r.ridership);
    return total / matching.length;
  }

  // Network-wide average daily ridership — from the "network_average"
  // view (a single pre-computed row), not by scanning the whole table.
  Future<double> getNetworkAverageRidership() async {
    if (_networkAverageCache != null) return _networkAverageCache!;
    final response = await Supabase.instance.client
        .from('network_average')
        .select('avg_ridership')
        .single();
    final avg = (response['avg_ridership'] as num).toDouble();
    _networkAverageCache = avg;
    return avg;
  }

  // ---------------------------------------------------------------------
  // Origin-Destination (O-D) ridership insights — backed by the
  // "od_totals" view (~16.6K pre-summed origin,destination,total_ridership
  // rows). Every method below sends a targeted query (filter, sort,
  // limit) and lets Postgres do the work — never loads the whole view.
  // Deliberately kept to simple filter/sort logic: no path-finding, no
  // multi-hop routes, no fare/ETA — that's Module 1's job (findRoutes,
  // above). This only answers "how many people travelled between two
  // named stations", never "how do I get from A to B".
  // ---------------------------------------------------------------------

  // Every station that has at least one real outgoing O-D record — from
  // the tiny "od_origins" view (~146 rows), never from od_totals itself.
  Future<List<String>> getStationsWithOutgoingData() async {
    if (_odOriginsCache != null) return _odOriginsCache!;
    final response = await Supabase.instance.client
        .from('od_origins')
        .select('origin')
        .order('origin');
    final origins = response.map((row) => row['origin'] as String).toList();
    _odOriginsCache = origins;
    return origins;
  }

  // Top [limit] destinations reached from [station] — filtered, sorted,
  // and limited entirely by Postgres. Only ever returns [limit] rows.
  Future<List<MapEntry<String, int>>> getTopDestinationsFrom(
      String station, {int limit = 5}) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('destination, total_ridership')
        .eq('origin', station)
        .order('total_ridership', ascending: false)
        .limit(limit);
    return response
        .map((row) => MapEntry(row['destination'] as String, (row['total_ridership'] as num).round()))
        .toList();
  }

  // Top [limit] origins that trips into [station] came from — same
  // pattern, filtered on destination instead.
  Future<List<MapEntry<String, int>>> getTopOriginsInto(
      String station, {int limit = 5}) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('origin, total_ridership')
        .eq('destination', station)
        .order('total_ridership', ascending: false)
        .limit(limit);
    return response
        .map((row) => MapEntry(row['origin'] as String, (row['total_ridership'] as num).round()))
        .toList();
  }

  // Total real outgoing trips from [station] — fetches only this
  // station's own rows (at most ~114, never the whole view), sums
  // client-side.
  Future<int> getTotalOutgoing(String station) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('total_ridership')
        .eq('origin', station);
    return response.fold<int>(0, (sum, row) => sum + (row['total_ridership'] as num).round());
  }

  // Total real incoming trips into [station].
  Future<int> getTotalIncoming(String station) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('total_ridership')
        .eq('destination', station);
    return response.fold<int>(0, (sum, row) => sum + (row['total_ridership'] as num).round());
  }

  // Network-wide leaderboard: busiest [limit] station-to-station
  // connections — one targeted query, sorted and limited by Postgres.
  Future<List<MapEntry<String, int>>> getBusiestConnections({int limit = 10}) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('origin, destination, total_ridership')
        .order('total_ridership', ascending: false)
        .limit(limit);
    return response
        .map((row) => MapEntry('${row['origin']} → ${row['destination']}', (row['total_ridership'] as num).round()))
        .toList();
  }

  // Simple status line shown at the top of the AI Crowd screen so users
  // can see the dataset actually loaded, instead of a fake "syncing" text.
  Future<String> getDatasetStatus() async {
    try {
      final stations = await getStationList();
      final odOrigins = await getStationsWithOutgoingData();
      if (stations.isEmpty) {
        return 'No ridership records found.';
      }
      return 'Loaded ${stations.length} stations, ${odOrigins.length} with O-D data from Supabase';
    } catch (e) {
      return 'Could not load ridership data from Supabase.';
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