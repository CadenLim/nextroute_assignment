// api_service.dart
import 'dart:math' show cos, sqrt, asin;
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;

import 'personal_assistance_functions.dart'; // 🌟 ADDED FRIEND'S FUNCTION

// =========================================================
// YOUR CODE (Module 1 / Journey Planning)
// =========================================================
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

// 🌟 LIVE VEHICLE MODEL
class LiveVehicle {
  final String id;
  final double lat;
  final double lon;
  final double bearing;
  final String routeId;
  final String licensePlate;

  LiveVehicle({
    required this.id, required this.lat, required this.lon,
    required this.bearing, required this.routeId, required this.licensePlate,
  });
}

// =========================================================
// FRIEND'S CODE (Module 3 / Crowd AI / Ridership)
// =========================================================
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
  final Map<String, List<RidershipRecord>> _stationRecordsCache = {};
  List<String>? _stationListCache;
  List<String>? _odOriginsCache;
  double? _networkAverageCache;
  List<({String station, double avgRidership, int totalRidership, int recordCount, DateTime? minDate, DateTime? maxDate})>? _stationRidershipTotalsCache;

  List<StationModel> _cachedStations = [];
  final Map<String, List<Map<String, dynamic>>> _allTripStopTimes = {};
  final Map<String, Map<String, dynamic>> _allRouteMetadata = {};
  final Map<String, String> _tripToRouteCache = {};
  bool _isGtfsFullyCached = false;

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
      'USJ7': 'USJ 7',
      'USJ 7 LRT': 'USJ 7',
      'USJ 7 BRT': 'USJ 7',
      'SUNWAY LAGOON BRT': 'SUNWAY LAGOON',
    };
    return map[cleanName] ?? cleanName;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var a = 0.5 - cos((lat2 - lat1) * p) / 2 + cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Duration _parseDuration(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 3) return Duration.zero;
    return Duration(hours: int.tryParse(parts[0]) ?? 0, minutes: int.tryParse(parts[1]) ?? 0, seconds: int.tryParse(parts[2]) ?? 0);
  }

  Future<void> _ensureGtfsFullyCached() async {
    if (_isGtfsFullyCached) return;
    for (String folder in ['rail', 'bus', 'mrt_feeder']) {
      try {
        final String rawRoutes = await rootBundle.loadString('assets/gtfs/$folder/routes.txt');
        _allRouteMetadata.addAll(_parseRouteMetadata(rawRoutes.replaceAll('\r\n', '\n'), folder));

        final String rawTrips = await rootBundle.loadString('assets/gtfs/$folder/trips.txt');
        final tripToRoute = _parseTrips(rawTrips.replaceAll('\r\n', '\n'), folder);
        _tripToRouteCache.addAll(tripToRoute);

        final String rawStopTimes = await rootBundle.loadString('assets/gtfs/$folder/stop_times.txt');
        _allTripStopTimes.addAll(_parseStopTimes(rawStopTimes.replaceAll('\r\n', '\n'), tripToRoute, folder));
      } catch (e) {
        debugPrint('GTFS load error for $folder: $e');
      }
    }
    _isGtfsFullyCached = true;
  }

  Future<List<StationModel>> loadAllStations() async {
    if (_cachedStations.isNotEmpty) return _cachedStations;

    await _ensureGtfsFullyCached();

    final Map<String, StationModel> stationMap = {};
    final Map<String, Set<String>> stopIdToRouteNames = {};

    for (final tripId in _allTripStopTimes.keys) {
      for (final stop in _allTripStopTimes[tripId]!) {
        final stopId = stop['stop_id'];
        final routeId = stop['route_id'];
        final routeName = _allRouteMetadata[routeId]?['short_name'] ?? routeId;
        stopIdToRouteNames.putIfAbsent(stopId, () => {});
        stopIdToRouteNames[stopId]!.add(routeName);
      }
    }

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
            else if (stopId.contains('_SB') || rawStopId.startsWith('SB') || rawStopId.startsWith('BRT') || stopName.contains('SUNWAY LAGOON')) {
              inferredLine = 'B1 (BRT Sunway)';
              category = 'Rail';
            }

            Set<String> actualRoutesServed = {inferredLine};
            if (stopIdToRouteNames.containsKey(stopId)) {
              for (final rName in stopIdToRouteNames[stopId]!) {
                if (!rName.toLowerCase().startsWith('bus_') &&
                    !rName.toLowerCase().startsWith('rail_') &&
                    !rName.toLowerCase().startsWith('mrt_feeder_')) {
                  actualRoutesServed.add(rName);
                }
              }
            }

            String mapKey = stopName;
            int suffix = 1;
            bool merged = false;

            while (stationMap.containsKey(mapKey)) {
              final existing = stationMap[mapKey]!;
              if (lat != 0.0 && lon != 0.0 && existing.lat != 0.0 && existing.lon != 0.0 &&
                  _calculateDistance(existing.lat, existing.lon, lat, lon) <= 0.25) {
                existing.ids.add(stopId);
                if (parentId != null) existing.ids.add(parentId);
                existing.lines.addAll(actualRoutesServed);
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
                ids: idsSet.toList(), name: stopName, lines: actualRoutesServed, category: category, lat: lat, lon: lon,
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

  List<String> _getIntermediateStops(List<Map<String, dynamic>> tripStops, int startIndex, int endIndex, Map<String, StationModel> stopIdToStation) {
    List<String> intermediateStops = [];
    if (startIndex >= 0 && endIndex > startIndex && (endIndex - startIndex) > 1) {
      for (int i = startIndex + 1; i < endIndex; i++) {
        final stm = stopIdToStation[tripStops[i]['stop_id']];
        if (stm != null && stm.name.isNotEmpty) {
          if (intermediateStops.isEmpty || intermediateStops.last != stm.name) {
            intermediateStops.add(stm.name);
          }
        }
      }
    }
    return intermediateStops;
  }

  Future<List<Map<String, dynamic>>> findRoutes(StationModel origin, StationModel destination) async {
    try {
      final List<Map<String, dynamic>> results = [];

      await _ensureGtfsFullyCached();

      final Map<String, StationModel> stopIdToStation = { for (var s in _cachedStations) for (var id in s.ids) id: s };
      final nowMinutes = DateTime.now().hour * 60 + DateTime.now().minute;

      int getWaitTime(int tripMins) {
        int w = tripMins - nowMinutes;
        return w < 0 ? w + 1440 : w;
      }

      Map<String, Map<String, dynamic>> bestDirect = {};
      Map<StationModel, Map<String, Map<String, dynamic>>> reachFromOrigin = {};
      Map<StationModel, Map<String, Map<String, dynamic>>> reachToDest = {};

      for (final tripId in _allTripStopTimes.keys) {
        final stops = _allTripStopTimes[tripId]!;
        if (stops.length < 2) continue;

        int oIdx = stops.indexWhere((s) => _matchesStation(origin, s['stop_id']));
        int dIdx = stops.lastIndexWhere((s) => _matchesStation(destination, s['stop_id']));

        if (oIdx != -1 && dIdx != -1 && oIdx < dIdx) {
          String rId = stops[oIdx]['route_id'];
          int oMins = _timeToMinutes(stops[oIdx]['arrival_time']);
          int wait = getWaitTime(oMins);

          if (!bestDirect.containsKey(rId) || wait < bestDirect[rId]!['wait']) {
            int dur = (_timeToMinutes(stops[dIdx]['arrival_time']) - oMins).abs();
            List<String> intermediates = _getIntermediateStops(stops, oIdx, dIdx, stopIdToStation);

            bestDirect[rId] = {
              'wait': wait,
              'dur': dur == 0 ? 15 : dur,
              'depart': stops[oIdx]['arrival_time'],
              'stops': intermediates,
            };
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
                List<String> intermediates = _getIntermediateStops(stops, oIdx, i, stopIdToStation);

                reachFromOrigin[stm]![rId] = {
                  'wait': wait,
                  'dur': dur == 0 ? 15 : dur,
                  'depart': stops[oIdx]['arrival_time'],
                  'stops': intermediates,
                };
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
                List<String> intermediates = _getIntermediateStops(stops, i, dIdx, stopIdToStation);

                reachToDest[stm]![rId] = {
                  'dur': dur == 0 ? 15 : dur,
                  'stops': intermediates,
                };
              }
            }
          }
        }
      }

      StationModel? wangsaMajuLrt;
      try { wangsaMajuLrt = _cachedStations.firstWhere((s) => s.name.contains('WANGSA MAJU') && s.category == 'Rail'); } catch (_) {}
      if ((origin.name.contains('PV15') || origin.name.contains('COLUMBIA')) && wangsaMajuLrt != null) {
        for (final rId in _allRouteMetadata.keys) {
          if (_allRouteMetadata[rId]!['short_name'] == '250' || _allRouteMetadata[rId]!['short_name'] == 'T250') {
            reachFromOrigin.putIfAbsent(wangsaMajuLrt, () => {});
            reachFromOrigin[wangsaMajuLrt]![rId] = {'wait': 5, 'dur': 12, 'depart': DateFormat('HH:mm').format(DateTime.now().add(const Duration(minutes: 5))), 'stops': ['KL East Mall', 'Taman Melati']};
          }
        }
      }

      for (final rId in bestDirect.keys) {
        final m = _allRouteMetadata[rId] ?? {'short_name': rId, 'color': Colors.blue, 'folder': 'bus'};
        final data = bestDirect[rId]!;
        final departStr = (data['depart'] as String).substring(0, 5);
        final List<String> intermediateNames = (data['stops'] as List<String>?) ?? [];

        results.add({
          'id': rId, 'name': m['short_name'], 'duration': '${data['dur']} min',
          'fare': 'RM ${(data['dur'] * 0.15 + 0.80).toStringAsFixed(2)}', 'badge': 'Direct', 'color': m['color'], 'sig': 'DIR_$rId',
          'wait': data['wait'], 'scheduledDepart': departStr,
          'legs': [
            {
              'mode': m['folder'] == 'rail' ? 'Rail' : 'Bus',
              'name': m['short_name'],
              'duration': '${data['dur']} min',
              'icon': m['folder'] == 'rail' ? Icons.train : Icons.directions_bus,
              'color': m['color'],
              'desc': 'Board ${m['short_name']} at ${origin.name} ($departStr)',
              'intermediate_stops': intermediateNames
            }
          ]
        });
      }

      for (final stm in reachFromOrigin.keys) {
        if (reachToDest.containsKey(stm)) {
          for (final r1Id in reachFromOrigin[stm]!.keys) {
            for (final r2Id in reachToDest[stm]!.keys) {
              if (r1Id == r2Id) continue;
              final m1 = _allRouteMetadata[r1Id] ?? {'short_name': r1Id, 'color': Colors.red, 'folder': 'bus'};
              final m2 = _allRouteMetadata[r2Id] ?? {'short_name': r2Id, 'color': Colors.blue, 'folder': 'rail'};

              int walkMins = (m1['folder'] == 'rail' && m2['folder'] == 'rail') ? 3 : 5;
              final d1 = reachFromOrigin[stm]![r1Id]!['dur'];
              final d2 = reachToDest[stm]![r2Id]!['dur'];
              final wait = reachFromOrigin[stm]![r1Id]!['wait'];
              final departStr = (reachFromOrigin[stm]![r1Id]!['depart'] as String).substring(0, 5);

              final List<String> iStops1 = (reachFromOrigin[stm]![r1Id]!['stops'] as List<String>?) ?? [];
              final List<String> iStops2 = (reachToDest[stm]![r2Id]!['stops'] as List<String>?) ?? [];

              final total = d1 + d2 + walkMins;

              results.add({
                'id': 'MIX', 'name': '${m1['short_name']} -> ${m2['short_name']} (via ${stm.name})',
                'duration': '$total min', 'fare': 'RM ${(total * 0.15 + 1.20).toStringAsFixed(2)}', 'badge': '1 Transfer', 'color': Colors.orange, 'sig': '1X_${m1['short_name']}_${stm.name}_${m2['short_name']}',
                'wait': wait, 'scheduledDepart': departStr,
                'legs': [
                  {
                    'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m1['short_name'], 'duration': '$d1 min',
                    'icon': m1['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m1['color'], 'desc': 'Board ${m1['short_name']} at ${origin.name} ($departStr)',
                    'intermediate_stops': iStops1
                  },
                  {
                    'mode': 'Walk', 'name': 'Interchange', 'duration': '$walkMins min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Transfer at ${stm.name}',
                  },
                  {
                    'mode': m2['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m2['short_name'], 'duration': '$d2 min',
                    'icon': m2['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m2['color'], 'desc': 'Board ${m2['short_name']} -> Arrive at ${destination.name}',
                    'intermediate_stops': iStops2
                  }
                ]
              });
            }
          }
        }
      }

      Map<StationModel, Map<StationModel, Map<String, dynamic>>> railBridges = {};
      for (final tripId in _allTripStopTimes.keys) {
        if (!tripId.startsWith('rail_')) continue;
        final stops = _allTripStopTimes[tripId]!;
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
              List<String> intermediates = _getIntermediateStops(stops, i, j, stopIdToStation);
              railBridges[stm1]![stm2] = {'rId': rId, 'dur': dur, 'stops': intermediates};
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

              final m1 = _allRouteMetadata[r1Id] ?? {'short_name': r1Id, 'color': Colors.red, 'folder': 'bus'};
              final m2 = _allRouteMetadata[bridge['rId']] ?? {'short_name': bridge['rId'], 'color': Colors.blue, 'folder': 'rail'};
              final m3 = _allRouteMetadata[r3Id] ?? {'short_name': r3Id, 'color': Colors.green, 'folder': 'rail'};

              int walk1 = (m1['folder'] == 'rail') ? 3 : 5;
              int walk2 = (m3['folder'] == 'rail') ? 3 : 5;

              final d1 = reachFromOrigin[stm1]![r1Id]!['dur'];
              final d2 = bridge['dur'];
              final d3 = reachToDest[stm2]![r3Id]!['dur'];
              final wait = reachFromOrigin[stm1]![r1Id]!['wait'];
              final departStr = (reachFromOrigin[stm1]![r1Id]!['depart'] as String).substring(0, 5);

              final List<String> iStops1 = (reachFromOrigin[stm1]![r1Id]!['stops'] as List<String>?) ?? [];
              final List<String> iStopsBridge = (bridge['stops'] as List<String>?) ?? [];
              final List<String> iStops3 = (reachToDest[stm2]![r3Id]!['stops'] as List<String>?) ?? [];

              results.add({
                'id': 'MIX2', 'name': '${m1['short_name']} -> ${m2['short_name']} -> ${m3['short_name']}',
                'duration': '${d1 + d2 + d3 + walk1 + walk2} min', 'fare': 'RM ${((d1 + d2 + d3) * 0.15 + 1.50).toStringAsFixed(2)}', 'badge': '2 Transfers', 'color': Colors.purple,
                'sig': '2X_${m1['short_name']}_${stm1.name}_${m2['short_name']}_${stm2.name}_${m3['short_name']}',
                'wait': wait, 'scheduledDepart': departStr,
                'legs': [
                  { 'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m1['short_name'], 'duration': '$d1 min', 'icon': m1['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m1['color'], 'desc': 'Board at ${origin.name} ($departStr)', 'intermediate_stops': iStops1 },
                  { 'mode': 'Walk', 'name': 'Transfer', 'duration': '$walk1 min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Transfer at ${stm1.name}' },
                  { 'mode': 'Rail', 'name': m2['short_name'], 'duration': '$d2 min', 'icon': Icons.train, 'color': m2['color'], 'desc': 'Connect via ${stm1.name}', 'intermediate_stops': iStopsBridge },
                  { 'mode': 'Walk', 'name': 'Transfer', 'duration': '$walk2 min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Transfer at ${stm2.name}' },
                  { 'mode': m3['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m3['short_name'], 'duration': '$d3 min', 'icon': m3['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m3['color'], 'desc': 'Arrive at ${destination.name}', 'intermediate_stops': iStops3 }
                ]
              });
            }
          }
        }
      }

      final Map<String, Map<String, dynamic>> uniqueResults = {};
      for (var r in results) {
        if (!uniqueResults.containsKey(r['sig']) ||
            int.parse(r['duration'].split(' ')[0]) < int.parse(uniqueResults[r['sig']]!['duration'].split(' ')[0])) {
          uniqueResults[r['sig']] = r;
        }
      }

      final finalResults = uniqueResults.values.toList();

      finalResults.sort((a, b) {
        int da = int.parse(a['duration'].split(' ')[0]);
        int db = int.parse(b['duration'].split(' ')[0]);

        int waitA = a['wait'] ?? 30;
        int waitB = b['wait'] ?? 30;

        int scoreA = da + waitA;
        int scoreB = db + waitB;

        if (a['badge'] == 'Direct') scoreA -= 2000;
        if (b['badge'] == 'Direct') scoreB -= 2000;

        bool aStartsWithBus = a['legs'].first['mode'] == 'Bus';
        bool bStartsWithBus = b['legs'].first['mode'] == 'Bus';
        bool aHasRail = a['legs'].any((l) => l['mode'] == 'Rail');
        bool bHasRail = b['legs'].any((l) => l['mode'] == 'Rail');

        // 🌟 NEW RULE: If user starts at a train station, heavily penalize taking a bus to another train!
        if (aStartsWithBus && aHasRail) scoreA += 500;
        if (bStartsWithBus && bHasRail) scoreB += 500;

        bool aEndsWithBus = a['legs'].last['mode'] == 'Bus';
        bool bEndsWithBus = b['legs'].last['mode'] == 'Bus';

        if (a['badge'] != 'Direct') {
          if (aEndsWithBus) scoreA += 50;
          if (!aHasRail) scoreA += 100;
        }
        if (b['badge'] != 'Direct') {
          if (bEndsWithBus) scoreB += 50;
          if (!bHasRail) scoreB += 100;
        }

        return scoreA.compareTo(scoreB);
      });

      return finalResults.take(4).toList();
    } catch (e) {
      debugPrint('Error finding routes: $e');
      return [];
    }
  }

  Map<String, Map<String, dynamic>> _parseRouteMetadata(String raw, String folder) {
    final lines = raw.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final Map<String, Map<String, dynamic>> metadata = {};
    if (lines.isEmpty) return metadata;

    final header = lines[0].split(',').map((e) => e.trim().replaceAll('"', '')).toList();
    final idIdx = header.indexOf('route_id');
    final shortNameIdx = header.indexOf('route_short_name');
    final longNameIdx = header.indexOf('route_long_name');
    final colorIdx = header.indexOf('route_color');

    for (final line in lines.skip(1)) {
      final parts = line.split(',').map((e) => e.trim().replaceAll('"', '')).toList();
      if (idIdx == -1 || idIdx >= parts.length) continue;

      final routeId = '${folder}_${parts[idIdx]}';

      String routeShortName = '';
      if (shortNameIdx != -1 && parts.length > shortNameIdx && parts[shortNameIdx].trim().isNotEmpty) {
        routeShortName = parts[shortNameIdx].trim();
      }
      if (routeShortName.isEmpty && longNameIdx != -1 && parts.length > longNameIdx && parts[longNameIdx].trim().isNotEmpty) {
        routeShortName = parts[longNameIdx].trim();
      }

      String effectiveFolder = folder;

      if (routeShortName.contains('BRT') || routeShortName.contains('SBL') || routeId.contains('SBL')) {
        routeShortName = 'B1 (BRT Sunway)';
        effectiveFolder = 'rail';
      }

      if (routeShortName.isEmpty || routeShortName.length > 10) {
        if (effectiveFolder == 'mrt_feeder') {
          routeShortName = 'MRT Feeder';
        } else if (effectiveFolder == 'bus') {
          routeShortName = 'Rapid Bus';
        } else {
          routeShortName = 'Transit Line';
        }
      }

      String routeColorHex = colorIdx != -1 && parts.length > colorIdx ? parts[colorIdx] : '';

      if (effectiveFolder == 'rail') {
        if (routeShortName.contains('Kelana Jaya') || routeShortName == 'KJL' || routeId.contains('KJL')) {
          routeShortName = 'Line 5 (Kelana Jaya)'; routeColorHex = 'E11D48';
        } else if (routeShortName.contains('Kajang') || routeShortName == 'KGL' || routeId.contains('KGL') || routeId.contains('SBK')) {
          routeShortName = 'Line 9 (Kajang)'; routeColorHex = '15803D';
        } else if (routeShortName.contains('Putrajaya') || routeShortName == 'PYL' || routeId.contains('PYL') || routeId.contains('SSP')) {
          routeShortName = 'Line 12 (Putrajaya)'; routeColorHex = 'EAB308';
        } else if (routeShortName.contains('Ampang') || routeShortName == 'AGL' || routeId.contains('AGL')) {
          routeShortName = 'Line 3 (Ampang)'; routeColorHex = 'F97316';
        } else if (routeShortName.contains('Sri Petaling') || routeShortName == 'SPL' || routeId.contains('SPL')) {
          routeShortName = 'Line 4 (Sri Petaling)'; routeColorHex = '7F1D1D';
        } else if (routeShortName.contains('Monorail') || routeShortName == 'MRL' || routeId.contains('MRL')) {
          routeShortName = 'Line 8 (Monorail)'; routeColorHex = '84CC16';
        } else if (routeShortName.contains('Sunway') || routeShortName.contains('BRT')) {
          routeShortName = 'B1 (BRT Sunway)'; routeColorHex = '14532D';
        } else if (routeShortName.contains('Seremban') || routeShortName == 'KTM Seremban') {
          routeShortName = 'Line 1 (Seremban)'; routeColorHex = '2563EB';
        } else if (routeShortName.contains('Port Klang') || routeShortName.contains('Pelabuhan')) {
          routeShortName = 'Line 2 (Port Klang)'; routeColorHex = 'DC2626';
        }
      }

      if (routeColorHex.isEmpty || routeColorHex.length != 6) {
        routeColorHex = effectiveFolder == 'rail' ? '2563EB' : '9CA3AF';
      }

      metadata[routeId] = {
        'short_name': routeShortName,
        'color': Color(int.parse('0xFF$routeColorHex')),
        'folder': effectiveFolder
      };
    }
    return metadata;
  }

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

  // 🌟 Database Fix: Use Friend's Edge Function to bypass RLS blocking
  Future<void> saveNavigationHistory({
    required String origin,
    required String destination,
    required double fare,
    required int durationMinutes,
    required String departureTime,
    required String estimatedArrivalTime,
    required List<Map<String, dynamic>> transitSteps,
    StationModel? originStation,
    StationModel? destinationStation,
    String routeSignature = '',
    String lineName = '',
  }) async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('User is not logged in. Please log in first.');

      await PersonalAssistanceFunctions().invoke(
        'journey-history',
        'insert',
        payload: {
          'journey': {
            'origin': origin,
            'destination': destination,
            'fare': fare,
            'currency': 'MYR',
            'duration_minutes': durationMinutes,
            'departure_time': departureTime,
            'estimated_arrival_time': estimatedArrivalTime,
            'transit_steps': transitSteps,
            'origin_station': originStation == null ? null : {
              'ids': originStation.ids.toList()..sort(),
              'name': originStation.name,
              'lines': originStation.lines.toList()..sort(),
              'category': originStation.category,
              'lat': originStation.lat,
              'lon': originStation.lon,
            },
            'destination_station': destinationStation == null ? null : {
              'ids': destinationStation.ids.toList()..sort(),
              'name': destinationStation.name,
              'lines': destinationStation.lines.toList()..sort(),
              'category': destinationStation.category,
              'lat': destinationStation.lat,
              'lon': destinationStation.lon,
            },
            'route_signature': routeSignature,
            'line_name': lineName,
            'status': 'completed',
          }
        },
      );
    } catch (e) {
      throw Exception('Failed to save navigation to database: ${e.toString()}');
    }
  }

  Future<List<LiveVehicle>> getLiveVehicles(String folder) async {
    try {
      String category = 'rapid-bus-kl';
      if (folder == 'mrt_feeder') category = 'rapid-bus-mrtfeeder';
      if (folder == 'rail') return [];

      await _ensureGtfsFullyCached();

      final response = await http.get(Uri.parse(
          'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=$category'));

      if (response.statusCode == 200) {
        final feedMessage = gtfs.FeedMessage.fromBuffer(response.bodyBytes);
        List<LiveVehicle> vehicles = [];

        for (var entity in feedMessage.entity) {
          if (entity.hasVehicle()) {
            final v = entity.vehicle;

            String rawRouteId = v.trip.hasRouteId() ? v.trip.routeId : '';
            String rawTripId = v.trip.hasTripId() ? v.trip.tripId : '';
            String vehicleLabel = v.vehicle.hasLabel() ? v.vehicle.label : '';

            String resolvedRouteId = '';

            if (rawRouteId.isNotEmpty) {
              resolvedRouteId = '${folder}_$rawRouteId';
            }

            if (resolvedRouteId.isEmpty || !_allRouteMetadata.containsKey(resolvedRouteId)) {
              resolvedRouteId = '';
              String fullTripId = '${folder}_$rawTripId';

              if (_tripToRouteCache.containsKey(fullTripId)) {
                resolvedRouteId = _tripToRouteCache[fullTripId]!;
              } else if (rawTripId.isNotEmpty) {
                String cleanRawTrip = rawTripId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
                if (cleanRawTrip.length > 5) {
                  for (String cachedTripId in _tripToRouteCache.keys) {
                    String cleanCached = cachedTripId.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
                    if (cleanCached.endsWith(cleanRawTrip) || cleanRawTrip.endsWith(cleanCached)) {
                      resolvedRouteId = _tripToRouteCache[cachedTripId]!;
                      break;
                    }
                  }
                }
              }
            }

            String routeName = _allRouteMetadata[resolvedRouteId]?['short_name'] ?? '';

            if (routeName.isEmpty && rawRouteId.isNotEmpty) {
              for (final meta in _allRouteMetadata.values) {
                if (meta['short_name'] == rawRouteId || meta['short_name'] == rawRouteId.toUpperCase()) {
                  routeName = meta['short_name'];
                  break;
                }
              }
            }

            if (routeName.isEmpty && rawRouteId.isNotEmpty) {
              for (final entry in _allRouteMetadata.entries) {
                if (entry.key.endsWith(rawRouteId) || entry.key.replaceAll(RegExp(r'[^0-9]'), '').endsWith(rawRouteId)) {
                  routeName = entry.value['short_name'];
                  break;
                }
              }
            }

            if (routeName.isEmpty && vehicleLabel.isNotEmpty) {
              for (final meta in _allRouteMetadata.values) {
                final sn = meta['short_name'];
                if (sn != null && sn.toString().length > 1 && vehicleLabel.toUpperCase().contains(sn.toString().toUpperCase())) {
                  routeName = sn;
                  break;
                }
              }
            }

            if (routeName.isEmpty) {
              routeName = rawRouteId.isNotEmpty ? rawRouteId : (v.vehicle.hasLicensePlate() ? v.vehicle.licensePlate : 'BUS');
            }

            vehicles.add(LiveVehicle(
              id: entity.id,
              lat: v.position.latitude,
              lon: v.position.longitude,
              bearing: v.position.hasBearing() ? v.position.bearing : 0.0,
              routeId: routeName,
              licensePlate: v.vehicle.hasLicensePlate() ? v.vehicle.licensePlate : 'Unknown',
            ));
          }
        }
        return vehicles;
      }
      return [];
    } catch (e) {
      debugPrint('GTFS-RT Error for $folder: $e');
      return [];
    }
  }

  // --- Analytics Below Unchanged ---
  static const String kAllStationsCode = 'A0: All Stations';

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
        continue;
      }
    }
    _stationRecordsCache[station] = records;
    return records;
  }

  Future<List<MapEntry<DateTime, int>>> getDailyTotalsForStation(String station) async {
    final records = await getStationTotalRecords(station);
    return records.map((r) => MapEntry(r.date, r.ridership)).toList();
  }

  Future<double> getStationAverageRidership(String station) async {
    final records = await getStationTotalRecords(station);
    if (records.isEmpty) return 0;
    final total = records.fold<int>(0, (sum, r) => sum + r.ridership);
    return total / records.length;
  }

  Future<double> getStationAverageForWeekday(String station, int weekday) async {
    final records = await getStationTotalRecords(station);
    final matching = records.where((r) => r.date.weekday == weekday).toList();
    if (matching.isEmpty) return getStationAverageRidership(station);
    final total = matching.fold<int>(0, (sum, r) => sum + r.ridership);
    return total / matching.length;
  }

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

  Future<List<({String station, double avgRidership, int totalRidership, int recordCount, DateTime? minDate, DateTime? maxDate})>>
  getStationRidershipTotals({DateTime? startDate, DateTime? endDate, bool forceRefresh = false}) async {
    final isOverall = startDate == null && endDate == null;
    if (isOverall && !forceRefresh && _stationRidershipTotalsCache != null) {
      return _stationRidershipTotalsCache!;
    }

    final List<Map<String, dynamic>> rows;
    if (isOverall) {
      rows = await Supabase.instance.client
          .from('station_ridership_totals')
          .select('station, avg_ridership, total_ridership, record_count, min_date, max_date')
          .order('avg_ridership', ascending: false);
    } else {
      rows = await Supabase.instance.client.rpc('station_ridership_totals_for_range', params: {
        'start_date': DateFormat('yyyy-MM-dd').format(startDate!),
        'end_date': DateFormat('yyyy-MM-dd').format(endDate!),
      });
    }

    final results = rows
        .map((row) => (
    station: row['station'] as String,
    avgRidership: (row['avg_ridership'] as num).toDouble(),
    totalRidership: (row['total_ridership'] as num).round(),
    recordCount: (row['record_count'] as num).round(),
    minDate: row['min_date'] != null ? DateTime.tryParse(row['min_date'] as String) : null,
    maxDate: row['max_date'] != null ? DateTime.tryParse(row['max_date'] as String) : null,
    ))
        .toList();

    if (isOverall) _stationRidershipTotalsCache = results;
    return results;
  }

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

  Future<int> getTotalOutgoing(String station) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('total_ridership')
        .eq('origin', station);
    return response.fold<int>(0, (sum, row) => sum + (row['total_ridership'] as num).round());
  }

  Future<int> getTotalIncoming(String station) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('total_ridership')
        .eq('destination', station);
    return response.fold<int>(0, (sum, row) => sum + (row['total_ridership'] as num).round());
  }

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