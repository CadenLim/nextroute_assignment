import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

class RidershipRecord {
  final DateTime date;
  final String origin;
  final String destination;
  final int ridership;

  RidershipRecord({required this.date, required this.origin, required this.destination, required this.ridership});
}

class ApiService {
  List<RidershipRecord>? _cache;
  List<StationModel> _cachedStations = [];

  String _cleanStationName(String rawName) {
    String name = rawName.trim().toUpperCase();
    name = name.replaceAll(RegExp(r'^\([^)]+\)\s*'), '');
    name = name.replaceAll(RegExp(r'^[A-Za-z]{1,4}\d+\s+'), '');
    name = name.replaceAll(RegExp(r'\s*\([^)]+\)'), '');
    if (name.contains('/')) name = name.split('/')[0].trim();
    if (name.contains('-')) name = name.split('-')[0].trim();
    name = name.replaceAll(RegExp(r'\b(STESEN|STATION|BUS TERMINAL|HUB)\b', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'\b(MRT|LRT|MONORAIL|KTM|BRT)\b', caseSensitive: false), '');
    name = name.replaceAll(RegExp(r'\bCONDOMINIUM\b', caseSensitive: false), 'CONDO');
    name = name.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (name.isEmpty) return rawName.trim().toUpperCase();
    return name;
  }

  Future<List<StationModel>> loadAllStations() async {
    final Map<String, StationModel> stationMap = {};
    final filePaths = ['assets/gtfs/rail/stops.txt', 'assets/gtfs/mrt_feeder/stops.txt', 'assets/gtfs/bus/stops.txt'];

    for (String path in filePaths) {
      try {
        final String raw = await rootBundle.loadString(path);
        List<List<dynamic>> csvTable = const CsvToListConverter(eol: '\n').convert(raw);
        if (csvTable.isEmpty) continue;

        final header = csvTable[0].map((e) => e.toString().trim()).toList();
        final idIndex = header.indexOf('stop_id');
        final nameIndex = header.indexOf('stop_name');
        final latIndex = header.indexOf('stop_lat');
        final lonIndex = header.indexOf('stop_lon');
        final parentIndex = header.indexOf('parent_station');

        if (idIndex == -1 || nameIndex == -1) continue;

        String folder = path.contains('rail') ? 'rail' : (path.contains('mrt_feeder') ? 'mrt_feeder' : 'bus');
        String category = path.contains('rail') ? 'Rail' : (path.contains('mrt_feeder') ? 'MRT Feeder' : 'Bus');

        for (int i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.length > nameIndex) {
            final rawStopId = row[idIndex].toString().trim();
            final stopId = '${folder}_$rawStopId';

            // STRICT: Only clean the name. No Master Interchange merging.
            final stopName = _cleanStationName(row[nameIndex].toString().trim());

            String? parentId;
            if (parentIndex != -1 && row.length > parentIndex && row[parentIndex].toString().trim().isNotEmpty) {
              parentId = '${folder}_${row[parentIndex].toString().trim()}';
            }

            double lat = 0.0, lon = 0.0;
            if (latIndex != -1 && lonIndex != -1 && row.length > lonIndex) {
              lat = double.tryParse(row[latIndex].toString()) ?? 0.0;
              lon = double.tryParse(row[lonIndex].toString()) ?? 0.0;
            }

            String inferredLine = category;
            if (stopId.contains('_KJ') || rawStopId.startsWith('KJ')) inferredLine = 'Line 5 (Kelana Jaya)';
            else if (stopId.contains('_KG') || rawStopId.startsWith('KG') || rawStopId.startsWith('SBK')) inferredLine = 'Line 9 (Kajang)';
            else if (stopId.contains('_AG') || rawStopId.startsWith('AG')) inferredLine = 'Line 3 (Ampang)';
            else if (stopId.contains('_SP') || rawStopId.startsWith('SP')) inferredLine = 'Line 4 (Sri Petaling)';
            else if (stopId.contains('_MR') || rawStopId.startsWith('MR')) inferredLine = 'Line 8 (Monorail)';
            else if (stopId.contains('_PY') || rawStopId.startsWith('PY') || rawStopId.startsWith('SSP')) inferredLine = 'Line 12 (Putrajaya)';

            // STRICT: Group ONLY if the exact name matches. No distance calculations.
            if (stationMap.containsKey(stopName)) {
              stationMap[stopName]!.ids.add(stopId);
              if (parentId != null) stationMap[stopName]!.ids.add(parentId);
              stationMap[stopName]!.lines.add(inferredLine);
              if (category == 'Rail' || category == 'MRT Feeder') stationMap[stopName]!.category = 'Rail';
            } else {
              final idsSet = {stopId};
              if (parentId != null) idsSet.add(parentId);
              stationMap[stopName] = StationModel(
                ids: idsSet.toList(),
                name: stopName,
                lines: {inferredLine},
                category: category,
                lat: lat,
                lon: lon,
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

  // STRICT ID MATCHING: Prevents KJ31 from colliding with KJ3
  bool _matchesStation(StationModel station, String stopId) {
    if (station.ids.contains(stopId)) return true;
    final cleanId = stopId.contains('_') ? stopId.split('_').sublist(1).join('_') : stopId;
    
    for (var id in station.ids) {
      final cleanStationId = id.contains('_') ? id.split('_').sublist(1).join('_') : id;
      // MUST Be an exact match. No startsWith() allowed.
      if (cleanStationId == cleanId) {
        return true;
      }
    }
    return false;
  }

  Future<List<Map<String, dynamic>>> findRoutes(StationModel origin, StationModel destination) async {
    try {
      final List<Map<String, dynamic>> results = [];
      final Set<String> seenSignatures = {};

      final Map<String, List<Map<String, dynamic>>> allTripStopTimes = {};
      final Map<String, Map<String, dynamic>> allRouteMetadata = {};
      final Map<String, StationModel> stopIdToStation = { for (var s in _cachedStations) for (var id in s.ids) id: s };

      for (final folder in ['rail', 'bus', 'mrt_feeder']) {
        try {
          final routesRaw = await rootBundle.loadString('assets/gtfs/$folder/routes.txt');
          allRouteMetadata.addAll(_parseRouteMetadata(routesRaw, folder));
          final tripsRaw = await rootBundle.loadString('assets/gtfs/$folder/trips.txt');
          final tripToRoute = _parseTrips(tripsRaw, folder);
          final stopTimesRaw = await rootBundle.loadString('assets/gtfs/$folder/stop_times.txt');
          allTripStopTimes.addAll(_parseStopTimes(stopTimesRaw, tripToRoute, folder));
        } catch (e) {
          debugPrint('GTFS folder $folder load error: $e');
        }
      }

      final nowMinutes = DateTime.now().hour * 60 + DateTime.now().minute;

      Map<StationModel, Map<String, dynamic>> reachableFromOrigin = {};
      Map<StationModel, Map<String, dynamic>> reachableToDest = {};
      final Map<String, Map<String, dynamic>> bestDirectTrips = {};

      // 1. Direct Route Search
      for (final tripId in allTripStopTimes.keys) {
        final stops = allTripStopTimes[tripId]!;
        if (stops.length < 2) continue;

        List<int> originIndices = [];
        List<int> destIndices = [];

        for (int i = 0; i < stops.length; i++) {
          if (_matchesStation(origin, stops[i]['stop_id'])) originIndices.add(i);
          if (_matchesStation(destination, stops[i]['stop_id'])) destIndices.add(i);
        }

        bool isLoopToStartHub = _matchesStation(destination, stops[0]['stop_id']);
        if (isLoopToStartHub && !destIndices.contains(stops.length - 1)) {
          destIndices.add(stops.length - 1);
        }

        for (int oIdx in originIndices) {
          for (int dIdx in destIndices) {
            if (oIdx < dIdx) {
              final originTimeStr = stops[oIdx]['arrival_time'];
              final destTimeStr = stops[dIdx]['arrival_time'];
              final originMinutes = _timeToMinutes(originTimeStr);

              int waitTime = originMinutes - nowMinutes;
              if (waitTime < 0) waitTime += 1440; 
              if (waitTime > 120) waitTime = 20; 

              final rId = stops[oIdx]['route_id'];
              final sig = 'DIR_$rId';
              final m = allRouteMetadata[rId] ?? {'short_name': rId, 'color': Colors.blue, 'folder': 'bus'};
              int dur = (_parseDuration(destTimeStr) - _parseDuration(originTimeStr)).inMinutes.abs();
              if (dur <= 0) dur = 15;

              final candidate = {
                'id': rId,
                'name': m['short_name'],
                'duration': '$dur min',
                'fare': m['folder'] == 'rail' 
                    ? 'RM ${(dur * 0.18 + 0.80).toStringAsFixed(2)}' 
                    : 'RM ${(dur * 0.12 + 0.90).toStringAsFixed(2)}',
                'badge': 'Direct',
                'color': m['color'],
                'sig': sig,
                'waitTime': waitTime,
                'scheduledDepart': originTimeStr.length >= 5 ? originTimeStr.substring(0, 5) : originTimeStr,
                'legs': [
                  {
                    'mode': m['folder'] == 'rail' ? 'Rail' : 'Bus',
                    'name': m['short_name'],
                    'duration': '$dur min',
                    'icon': m['folder'] == 'rail' ? Icons.train : Icons.directions_bus,
                    'color': m['color'],
                    'desc': 'Board ${m['short_name']} at ${origin.name} ($originTimeStr) -> Arrive at ${destination.name}'
                  }
                ]
              };

              if (!bestDirectTrips.containsKey(rId) || dur < int.parse(bestDirectTrips[rId]!['duration'].split(' ')[0])) {
                bestDirectTrips[rId] = candidate;
              }
            }
          }
        }

        // Direct population of transfer reachability
        for (int oIdx in originIndices) {
          final rId = stops[oIdx]['route_id'];
          final originTimeStr = stops[oIdx]['arrival_time'];
          for (int j = oIdx + 1; j < stops.length; j++) {
            final stm = stopIdToStation[stops[j]['stop_id']];
            if (stm != null) {
              reachableFromOrigin.putIfAbsent(stm, () => {});
              int dur = (_parseDuration(stops[j]['arrival_time']) - _parseDuration(stops[oIdx]['arrival_time'])).inMinutes.abs();
              if (dur <= 0) dur = 15;
              if (!reachableFromOrigin[stm]!.containsKey(rId) || dur < reachableFromOrigin[stm]![rId]!['dur']) {
                reachableFromOrigin[stm]![rId] = {
                  'dur': dur,
                  'depart': originTimeStr.length >= 5 ? originTimeStr.substring(0, 5) : originTimeStr,
                };
              }
            }
          }
        }

        for (int dIdx in destIndices) {
          final rId = stops[dIdx]['route_id'];
          for (int j = 0; j < dIdx; j++) {
            final stm = stopIdToStation[stops[j]['stop_id']];
            if (stm != null) {
              reachableToDest.putIfAbsent(stm, () => {});
              int dur = (_parseDuration(stops[dIdx]['arrival_time']) - _parseDuration(stops[j]['arrival_time'])).inMinutes.abs();
              if (dur <= 0) dur = 15;
              if (!reachableToDest[stm]!.containsKey(rId) || dur < reachableToDest[stm]![rId]!['dur']) {
                reachableToDest[stm]![rId] = {'dur': dur};
              }
            }
          }
        }
      }

      results.addAll(bestDirectTrips.values);

      // 2. 1-Transfer Route Search
      for (final stm in reachableFromOrigin.keys) {
        if (reachableToDest.containsKey(stm)) {
          for (final r1Id in reachableFromOrigin[stm]!.keys) {
            for (final r2Id in reachableToDest[stm]!.keys) {
              if (r1Id == r2Id) continue;
              final m1 = allRouteMetadata[r1Id] ?? {'short_name': r1Id, 'color': Colors.red, 'folder': 'bus'};
              final m2 = allRouteMetadata[r2Id] ?? {'short_name': r2Id, 'color': Colors.blue, 'folder': 'rail'};

              final sig = '1X_${m1['short_name']}_via_${stm.name}_${m2['short_name']}';
              if (!seenSignatures.contains(sig)) {
                seenSignatures.add(sig);
                final oData = reachableFromOrigin[stm]![r1Id]; final dData = reachableToDest[stm]![r2Id];
                final d1 = oData['dur']; final d2 = dData['dur'];

                int walkPenalty = stm.category == 'Rail' ? 3 : 8; 
                final total = d1 + d2 + walkPenalty;
                final departStr = oData['depart'];

                results.add({
                  'id': 'MIX',
                  'name': '${m1['short_name']} + ${m2['short_name']}',
                  'duration': '$total min',
                  'fare': 'RM ${(total * 0.15 + 1.20).toStringAsFixed(2)}',
                  'badge': '1 Transfer',
                  'color': Colors.orange,
                  'sig': sig,
                  'waitTime': 15, 
                  'scheduledDepart': departStr,
                  'legs': [
                    { 'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m1['short_name'], 'duration': '$d1 min', 'icon': m1['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m1['color'], 'desc': 'Board ${m1['short_name']} at ${origin.name} ($departStr)' },
                    { 'mode': 'Walk', 'name': 'Interchange', 'duration': '$walkPenalty min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Interchange at ${stm.name}' },
                    { 'mode': m2['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m2['short_name'], 'duration': '$d2 min', 'icon': m2['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m2['color'], 'desc': 'Board ${m2['short_name']} -> Arrive at ${destination.name}' }
                  ]
                });
              }
            }
          }
        }
      }

      // 3. Graph Expansion: 2-Transfer Search
      if (results.isEmpty || results.length < 3) {
        for (final tripId in allTripStopTimes.keys) {
          final stops = allTripStopTimes[tripId]!;
          for (int i = 0; i < stops.length; i++) {
            final stm1 = stopIdToStation[stops[i]['stop_id']];
            if (stm1 != null && reachableFromOrigin.containsKey(stm1)) {
              for (int j = i + 1; j < stops.length; j++) {
                final stm2 = stopIdToStation[stops[j]['stop_id']];
                if (stm2 != null && reachableToDest.containsKey(stm2)) {
                  
                  final r1Id = reachableFromOrigin[stm1]!.keys.first;
                  final r2Id = stops[i]['route_id'];
                  final r3Id = reachableToDest[stm2]!.keys.first;
                  
                  if (r1Id == r2Id || r2Id == r3Id) continue; 
                  
                  final m1 = allRouteMetadata[r1Id] ?? {'short_name': r1Id, 'color': Colors.grey, 'folder': 'bus'};
                  final m2 = allRouteMetadata[r2Id] ?? {'short_name': r2Id, 'color': Colors.grey, 'folder': 'rail'};
                  final m3 = allRouteMetadata[r3Id] ?? {'short_name': r3Id, 'color': Colors.grey, 'folder': 'rail'};

                  int d1 = reachableFromOrigin[stm1]![r1Id]['dur'];
                  int d2 = (_parseDuration(stops[j]['arrival_time']) - _parseDuration(stops[i]['arrival_time'])).inMinutes.abs();
                  if (d2 <= 0) d2 = 15;
                  int d3 = reachableToDest[stm2]![r3Id]['dur'];
                  final departStr = reachableFromOrigin[stm1]![r1Id]['depart'];

                  if (m2['short_name'] == m3['short_name'] && m2['folder'] == 'rail') {
                    final sig = '1X_FIX_${m1['short_name']}_${m2['short_name']}';
                    if (!seenSignatures.contains(sig)) {
                      seenSignatures.add(sig);
                      int total = d1 + d2 + d3 + 5; 
                      results.add({
                        'id': 'MIX_FIX',
                        'name': '${m1['short_name']} + ${m2['short_name']}',
                        'duration': '$total min',
                        'fare': 'RM ${(total * 0.15 + 1.20).toStringAsFixed(2)}',
                        'badge': '1 Transfer',
                        'color': Colors.orange,
                        'sig': sig,
                        'waitTime': 15,
                        'scheduledDepart': departStr,
                        'legs': [
                          { 'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m1['short_name'], 'duration': '$d1 min', 'icon': m1['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m1['color'], 'desc': 'Board ${m1['short_name']} at ${origin.name}' },
                          { 'mode': 'Walk', 'name': 'Interchange', 'duration': '5 min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Interchange at ${stm1.name}' },
                          { 'mode': m2['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m2['short_name'], 'duration': '${d2 + d3} min', 'icon': m2['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m2['color'], 'desc': 'Board ${m2['short_name']} -> Arrive at ${destination.name}' }
                        ]
                      });
                    }
                  } else {
                    final sig = '2X_${m1['short_name']}_${m2['short_name']}_${m3['short_name']}';
                    if (!seenSignatures.contains(sig)) {
                      seenSignatures.add(sig);
                      int walkPenalty = 10;
                      int total = d1 + d2 + d3 + walkPenalty;
                      results.add({
                        'id': 'MIX2',
                        'name': '${m1['short_name']} > ${m2['short_name']} > ${m3['short_name']}',
                        'duration': '$total min',
                        'fare': 'RM ${(total * 0.15 + 1.50).toStringAsFixed(2)}',
                        'badge': '2 Transfers',
                        'color': Colors.purple,
                        'sig': sig,
                        'waitTime': 20,
                        'scheduledDepart': departStr,
                        'legs': [
                          { 'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m1['short_name'], 'duration': '$d1 min', 'icon': m1['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m1['color'], 'desc': 'Board ${m1['short_name']} at ${origin.name}' },
                          { 'mode': 'Walk', 'name': 'Transfer', 'duration': '5 min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Interchange at ${stm1.name}' },
                          { 'mode': m2['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m2['short_name'], 'duration': '$d2 min', 'icon': m2['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m2['color'], 'desc': 'Board ${m2['short_name']} to ${stm2.name}' },
                          { 'mode': 'Walk', 'name': 'Transfer', 'duration': '5 min', 'icon': Icons.directions_walk, 'color': Colors.grey, 'desc': 'Interchange at ${stm2.name}' },
                          { 'mode': m3['folder'] == 'rail' ? 'Rail' : 'Bus', 'name': m3['short_name'], 'duration': '$d3 min', 'icon': m3['folder'] == 'rail' ? Icons.train : Icons.directions_bus, 'color': m3['color'], 'desc': 'Board ${m3['short_name']} -> Arrive at ${destination.name}' }
                        ]
                      });
                    }
                  }
                }
              }
            }
          }
        }
      }

      // 4. Sorting & Prioritization
      final Map<String, Map<String, dynamic>> uniqueResults = {};
      for (var r in results) {
        String key = r['sig'];
        if (!uniqueResults.containsKey(key) ||
            int.parse(r['duration'].split(' ')[0]) < int.parse(uniqueResults[key]!['duration'].split(' ')[0])) {
          uniqueResults[key] = r;
        }
      }
      final finalResults = uniqueResults.values.toList();

      finalResults.sort((a, b) {
        int durationA = int.parse(a['duration'].split(' ')[0]);
        int durationB = int.parse(b['duration'].split(' ')[0]);

        int waitA = a['waitTime'] ?? 20;
        int waitB = b['waitTime'] ?? 20;

        bool aIsDirect = a['badge'] == 'Direct';
        bool bIsDirect = b['badge'] == 'Direct';

        bool aUsesRail = a['legs'].any((leg) => leg['mode'] == 'Rail');
        bool bUsesRail = b['legs'].any((leg) => leg['mode'] == 'Rail');

        int scoreA = durationA + waitA;
        int scoreB = durationB + waitB;

        // Rail Priority
        if (aIsDirect) scoreA -= 200;
        if (bIsDirect) scoreB -= 200;
        
        if (aUsesRail) scoreA -= 150; 
        if (bUsesRail) scoreB -= 150;

        if (a['badge'] == '2 Transfers') scoreA += 100;
        if (b['badge'] == '2 Transfers') scoreB += 100;

        return scoreA.compareTo(scoreB);
      });

      return finalResults.take(10).toList();
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
    final colorIdx = header.indexOf('route_color');

    for (final line in lines.skip(1)) {
      final parts = line.split(',').map((e) => e.trim().replaceAll('"', '')).toList();
      if (parts.length <= shortNameIdx || idIdx == -1 || idIdx >= parts.length) continue;
      
      final routeId = '${folder}_${parts[idIdx]}';
      String routeShortName = parts[shortNameIdx].isNotEmpty ? parts[shortNameIdx] : parts[idIdx]; 
      String routeColorHex = colorIdx != -1 && parts.length > colorIdx ? parts[colorIdx] : '';
      
      if (folder == 'rail') {
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
        } else if (routeShortName.contains('Sunway') || routeShortName == 'BRT') {
          routeShortName = 'B1 (BRT Sunway)'; routeColorHex = '14532D'; 
        } else if (routeShortName.contains('Seremban') || routeShortName == 'KTM Seremban') {
          routeShortName = 'Line 1 (Seremban)'; routeColorHex = '2563EB'; 
        } else if (routeShortName.contains('Port Klang') || routeShortName.contains('Pelabuhan')) {
          routeShortName = 'Line 2 (Port Klang)'; routeColorHex = 'DC2626'; 
        }
      }

      if (routeColorHex.isEmpty || routeColorHex.length != 6) {
        routeColorHex = folder == 'rail' ? '2563EB' : '9CA3AF';
      }

      metadata[routeId] = {
        'short_name': routeShortName,
        'color': Color(int.parse('0xFF$routeColorHex')),
        'folder': folder
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

  Duration _parseDuration(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 3) return Duration.zero;
    return Duration(hours: int.tryParse(parts[0]) ?? 0, minutes: int.tryParse(parts[1]) ?? 0, seconds: int.tryParse(parts[2]) ?? 0);
  }

  Future<List<RidershipRecord>> loadRidership() async {
    if (_cache != null) return _cache!;
    final String raw = await rootBundle.loadString('assets/ridership.csv');
    final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final records = <RidershipRecord>[];
    for (final line in lines.skip(1)) {
      final parts = line.split(',');
      if (parts.length < 4) continue;
      try { records.add(RidershipRecord(origin: parts[0].trim(), destination: parts[1].trim(), date: DateTime.parse(parts[2].trim()), ridership: double.parse(parts[3].trim()).round())); } catch (_) {}
    }
    return _cache = records;
  }

  static const String kAllStationsCode = 'A0: All Stations';

  Future<List<String>> getStationList() async {
    final all = await loadRidership();
    final names = all.where((r) => r.origin == kAllStationsCode).map((r) => r.destination).toSet().toList();
    names.sort(); return names;
  }

  Future<List<RidershipRecord>> getStationTotalRecords(String station) async {
    final all = await loadRidership();
    return all.where((r) => r.origin == kAllStationsCode && r.destination == station).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<List<MapEntry<DateTime, int>>> getDailyTotalsForStation(String station) async {
    final records = await getStationTotalRecords(station);
    final Map<DateTime, int> totals = {};
    for (final r in records) {
      final day = DateTime(r.date.year, r.date.month, r.date.day);
      totals[day] = (totals[day] ?? 0) + r.ridership;
    }
    final entries = totals.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  Future<double> getStationAverageRidership(String station) async {
    final daily = await getDailyTotalsForStation(station);
    if (daily.isEmpty) return 0;
    return daily.fold<int>(0, (sum, e) => sum + e.value) / daily.length;
  }

  Future<double> getStationAverageForWeekday(String station, int weekday) async {
    final daily = await getDailyTotalsForStation(station);
    final matching = daily.where((e) => e.key.weekday == weekday).toList();
    if (matching.isEmpty) return getStationAverageRidership(station);
    return matching.fold<int>(0, (sum, e) => sum + e.value) / matching.length;
  }

  Future<double> getNetworkAverageRidership() async {
    final all = await loadRidership();
    final totals = all.where((r) => r.origin == kAllStationsCode).toList();
    if (totals.isEmpty) return 1;
    return totals.fold<int>(0, (s, r) => s + r.ridership) / totals.length;
  }

  Future<List<String>> getStationsWithOutgoingData() async {
    final all = await loadRidership();
    final origins = all.where((r) => r.origin != kAllStationsCode && r.destination != kAllStationsCode).map((r) => r.origin).toSet().toList();
    origins.sort(); return origins;
  }

  Future<List<MapEntry<String, int>>> getTopDestinationsFrom(String station, {int limit = 5}) async {
    final all = await loadRidership();
    final Map<String, int> totals = {};
    for (final r in all) { if (r.origin == station && r.destination != kAllStationsCode) totals[r.destination] = (totals[r.destination] ?? 0) + r.ridership; }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  Future<List<MapEntry<String, int>>> getTopOriginsInto(String station, {int limit = 5}) async {
    final all = await loadRidership();
    final Map<String, int> totals = {};
    for (final r in all) { if (r.destination == station && r.origin != kAllStationsCode) totals[r.origin] = (totals[r.origin] ?? 0) + r.ridership; }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  Future<int> getTotalOutgoing(String station) async {
    final all = await loadRidership();
    return all.where((r) => r.origin == station && r.destination != kAllStationsCode).fold<int>(0, (s, r) => s + r.ridership);
  }

  Future<int> getTotalIncoming(String station) async {
    final all = await loadRidership();
    return all.where((r) => r.destination == station && r.origin != kAllStationsCode).fold<int>(0, (s, r) => s + r.ridership);
  }

  Future<List<MapEntry<String, int>>> getBusiestConnections({int limit = 10}) async {
    final all = await loadRidership();
    final Map<String, int> totals = {};
    for (final r in all) {
      if (r.origin == kAllStationsCode || r.destination == kAllStationsCode) continue;
      final key = '${r.origin} → ${r.destination}';
      totals[key] = (totals[key] ?? 0) + r.ridership;
    }
    final entries = totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(limit).toList();
  }

  Future<String> getDatasetStatus() async {
    try {
      final records = await loadRidership();
      if (records.isEmpty) return 'No ridership records found in local dataset.';
      return 'Local dataset loaded: ${records.length} ridership records';
    } catch (e) { return 'Could not load local ridership dataset.'; }
  }

  Future<String> getRealtimeBusPositions() async {
    try {
      final response = await http.get(Uri.parse('https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl'));
      if (response.statusCode == 200) return 'Connected: Received ${response.bodyBytes.length} bytes of live data';
      return 'Failed to load live data';
    } catch (e) { return 'API Connection Error'; }
  }

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
}