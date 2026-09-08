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
import 'gtfs_route_timetable.dart';

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
    required this.ids,
    required this.name,
    required this.lines,
    required this.category,
    required this.lat,
    required this.lon,
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
    required this.id,
    required this.lat,
    required this.lon,
    required this.bearing,
    required this.routeId,
    required this.licensePlate,
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
  List<
    ({
      String station,
      double avgRidership,
      int totalRidership,
      int recordCount,
      DateTime? minDate,
      DateTime? maxDate,
    })
  >?
  _stationRidershipTotalsCache;

  List<StationModel> _cachedStations = [];
  final Map<String, List<Map<String, dynamic>>> _allTripStopTimes = {};
  final Map<String, Map<String, dynamic>> _allRouteMetadata = {};
  final Map<String, String> _tripToRouteCache = {};
  final Map<String, String> _tripToShapeCache = {};
  final Map<String, String> _tripToServiceCache = {};
  final Map<String, List<GtfsFrequencyWindow>> _tripFrequencies = {};
  final Map<String, GtfsServiceCalendar> _serviceCalendars = {};
  final Map<String, Map<int, bool>> _calendarExceptions = {};
  bool _isGtfsFullyCached = false;

  String _cleanStationName(String rawName) {
    String name = rawName.trim().toUpperCase();
    name = name.replaceAll(RegExp(r'^[A-Za-z]{1,4}\d+\s*[-–]?\s*'), '');
    name = name.replaceAll(RegExp(r'^\([^)]+\)\s*'), '');
    name = name.replaceAll(RegExp(r'\s*\([^)]+\)'), '');
    name = name.replaceAll(
      RegExp(
        r'\b(STESEN|STATION|BUS TERMINAL|HUB|HENTIAN)\b',
        caseSensitive: false,
      ),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\b(MRT|LRT|MONORAIL|KTM|BRT)\b', caseSensitive: false),
      '',
    );
    name = name.replaceAll(
      RegExp(r'\bCONDOMINIUM\b', caseSensitive: false),
      'CONDO',
    );
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

  double _calculateDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    var p = 0.017453292519943295;
    var a =
        0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a));
  }

  Duration _parseDuration(String timeStr) {
    final parts = timeStr.split(':');
    if (parts.length != 3) return Duration.zero;
    return Duration(
      hours: int.tryParse(parts[0]) ?? 0,
      minutes: int.tryParse(parts[1]) ?? 0,
      seconds: int.tryParse(parts[2]) ?? 0,
    );
  }

  Future<void> _ensureGtfsFullyCached() async {
    if (_isGtfsFullyCached) return;
    for (String folder in ['rail', 'bus', 'mrt_feeder']) {
      try {
        final String rawRoutes = await rootBundle.loadString(
          'assets/gtfs/$folder/routes.txt',
        );
        _allRouteMetadata.addAll(
          _parseRouteMetadata(rawRoutes.replaceAll('\r\n', '\n'), folder),
        );

        final String rawTrips = await rootBundle.loadString(
          'assets/gtfs/$folder/trips.txt',
        );
        final tripToRoute = _parseTrips(
          rawTrips.replaceAll('\r\n', '\n'),
          folder,
        );
        _tripToRouteCache.addAll(tripToRoute);

        final String rawStopTimes = await rootBundle.loadString(
          'assets/gtfs/$folder/stop_times.txt',
        );
        _allTripStopTimes.addAll(
          _parseStopTimes(
            rawStopTimes.replaceAll('\r\n', '\n'),
            tripToRoute,
            folder,
          ),
        );

        try {
          final rawFrequencies = await rootBundle.loadString(
            'assets/gtfs/$folder/frequencies.txt',
          );
          _tripFrequencies.addAll(_parseFrequencies(rawFrequencies, folder));
        } catch (_) {
          // frequencies.txt is optional in GTFS. Fixed trips remain usable.
        }

        try {
          final rawExceptions = await rootBundle.loadString(
            'assets/gtfs/$folder/calendar_dates.txt',
          );
          _calendarExceptions.addAll(
            _parseCalendarExceptions(rawExceptions, folder),
          );
        } catch (_) {
          // calendar_dates.txt is optional when calendar.txt is complete.
        }

        final rawCalendar = await rootBundle.loadString(
          'assets/gtfs/$folder/calendar.txt',
        );
        _serviceCalendars.addAll(_parseCalendars(rawCalendar, folder));
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

    final filePaths = [
      'assets/gtfs/rail/stops.txt',
      'assets/gtfs/mrt_feeder/stops.txt',
      'assets/gtfs/bus/stops.txt',
    ];

    for (String path in filePaths) {
      try {
        final String rawFile = await rootBundle.loadString(path);
        final String safeRaw = rawFile.replaceAll('\r\n', '\n');

        List<List<dynamic>> csvTable = const CsvToListConverter(
          eol: '\n',
          shouldParseNumbers: false,
        ).convert(safeRaw.replaceAll('\uFEFF', ''));
        if (csvTable.isEmpty) continue;

        final header = csvTable[0]
            .map((e) => e.toString().trim().toLowerCase())
            .toList();

        int idIndex = header.indexOf('stop_id');
        if (idIndex == -1) idIndex = 0;
        int nameIndex = header.indexOf('stop_name');
        if (nameIndex == -1) nameIndex = 1;
        int latIndex = header.indexOf('stop_lat');
        if (latIndex == -1) latIndex = 2;
        int lonIndex = header.indexOf('stop_lon');
        if (lonIndex == -1) lonIndex = 3;
        int parentIndex = header.indexOf('parent_station');

        String folder = path.contains('rail')
            ? 'rail'
            : (path.contains('mrt_feeder') ? 'mrt_feeder' : 'bus');
        String category = path.contains('rail')
            ? 'Rail'
            : (path.contains('mrt_feeder') ? 'MRT Feeder' : 'Bus');

        for (int i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.length > nameIndex) {
            final rawStopId = row[idIndex].toString().trim();
            if (rawStopId.isEmpty) continue;

            final stopId = '${folder}_$rawStopId';
            final stopNameClean = _cleanStationName(
              row[nameIndex].toString().trim(),
            );
            final stopName = _normalizeToMasterInterchange(stopNameClean);

            String? parentId;
            if (parentIndex != -1 &&
                row.length > parentIndex &&
                row[parentIndex].toString().trim().isNotEmpty) {
              parentId = '${folder}_${row[parentIndex].toString().trim()}';
            }

            double lat = 0.0, lon = 0.0;
            if (latIndex != -1 && row.length > latIndex)
              lat = double.tryParse(row[latIndex].toString()) ?? 0.0;
            if (lonIndex != -1 && row.length > lonIndex)
              lon = double.tryParse(row[lonIndex].toString()) ?? 0.0;

            String inferredLine = category;
            if (stopId.contains('_KJ') || rawStopId.startsWith('KJ'))
              inferredLine = 'Line 5 (Kelana Jaya)';
            else if (stopId.contains('_KG') ||
                rawStopId.startsWith('KG') ||
                rawStopId.startsWith('SBK'))
              inferredLine = 'Line 9 (Kajang)';
            else if (stopId.contains('_AG') || rawStopId.startsWith('AG'))
              inferredLine = 'Line 3 (Ampang)';
            else if (stopId.contains('_SP') || rawStopId.startsWith('SP'))
              inferredLine = 'Line 4 (Sri Petaling)';
            else if (stopId.contains('_MR') || rawStopId.startsWith('MR'))
              inferredLine = 'Line 8 (Monorail)';
            else if (stopId.contains('_PY') ||
                rawStopId.startsWith('PY') ||
                rawStopId.startsWith('SSP'))
              inferredLine = 'Line 12 (Putrajaya)';
            else if (stopId.contains('_SB') ||
                rawStopId.startsWith('SB') ||
                rawStopId.startsWith('BRT') ||
                stopName.contains('SUNWAY LAGOON')) {
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
              if (lat != 0.0 &&
                  lon != 0.0 &&
                  existing.lat != 0.0 &&
                  existing.lon != 0.0 &&
                  _calculateDistance(existing.lat, existing.lon, lat, lon) <=
                      0.25) {
                existing.ids.add(stopId);
                if (parentId != null) existing.ids.add(parentId);
                existing.lines.addAll(actualRoutesServed);
                if (category == 'Rail') existing.category = 'Rail';
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
                ids: idsSet.toList(),
                name: stopName,
                lines: actualRoutesServed,
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

  bool _matchesStation(StationModel station, String stopId) {
    if (station.ids.contains(stopId)) return true;
    final cleanId = stopId.contains('_')
        ? stopId.split('_').sublist(1).join('_')
        : stopId;
    for (var id in station.ids) {
      final cleanStationId = id.contains('_')
          ? id.split('_').sublist(1).join('_')
          : id;
      if (cleanStationId == cleanId) return true;
    }
    return false;
  }

  List<String> _getIntermediateStops(
    List<Map<String, dynamic>> tripStops,
    int startIndex,
    int endIndex,
    Map<String, StationModel> stopIdToStation,
  ) {
    List<String> intermediateStops = [];
    if (startIndex >= 0 &&
        endIndex > startIndex &&
        (endIndex - startIndex) > 1) {
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

  // Fixed/stage-fare approximation, keyed on straight-line distance rather than
  // elapsed minutes. Rapid Bus & Rail fares are set by distance/zone, not by
  // how long the vehicle took to get there (which moves with traffic) — a
  // duration-based formula overcharges a route stuck in a jam and undercharges
  // a lucky fast one, which is backwards.
  //
  // These tier boundaries are a reasonable placeholder, not a confirmed source
  // of truth for the exact current fare. If assets/gtfs/<folder>/ ships
  // fare_attributes.txt / fare_rules.txt, prefer looking the fare up there —
  // that's Prasarana's own published price per fare_id and will always be
  // more accurate than a hand-tuned table.
  double _fareForLeg(String folder, double distanceKm) {
    if (folder == 'rail') {
      if (distanceKm <= 4) return 1.10;
      if (distanceKm <= 8) return 1.60;
      if (distanceKm <= 12) return 2.10;
      if (distanceKm <= 18) return 2.80;
      if (distanceKm <= 25) return 3.60;
      if (distanceKm <= 35) return 4.60;
      return 6.40;
    }
    if (folder == 'mrt_feeder') return 1.00; // Feeder buses: flat RM1.
    if (distanceKm <= 4) return 1.00;
    if (distanceKm <= 10) return 2.00;
    return 3.00;
  }

  Future<List<Map<String, dynamic>>> findRoutes(
    StationModel origin,
    StationModel destination,
  ) async {
    try {
      final List<Map<String, dynamic>> results = [];

      await _ensureGtfsFullyCached();

      final Map<String, StationModel> stopIdToStation = {
        for (var s in _cachedStations)
          for (var id in s.ids) id: s,
      };
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

        int oIdx = stops.indexWhere(
          (s) => _matchesStation(origin, s['stop_id']),
        );
        int dIdx = stops.lastIndexWhere(
          (s) => _matchesStation(destination, s['stop_id']),
        );

        if (oIdx != -1 && dIdx != -1 && oIdx < dIdx) {
          String rId = stops[oIdx]['route_id'];
          int oMins = _timeToMinutes(stops[oIdx]['arrival_time']);
          int wait = getWaitTime(oMins);

          if (!bestDirect.containsKey(rId) || wait < bestDirect[rId]!['wait']) {
            int dur = (_timeToMinutes(stops[dIdx]['arrival_time']) - oMins)
                .abs();
            List<String> intermediates = _getIntermediateStops(
              stops,
              oIdx,
              dIdx,
              stopIdToStation,
            );

            bestDirect[rId] = {
              'wait': wait,
              'dur': dur == 0 ? 15 : dur,
              'depart': stops[oIdx]['arrival_time'],
              'stops': intermediates,
              'trip': tripId,
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
              if (!reachFromOrigin[stm]!.containsKey(rId) ||
                  wait < reachFromOrigin[stm]![rId]!['wait']) {
                int dur = (_timeToMinutes(stops[i]['arrival_time']) - oMins)
                    .abs();
                List<String> intermediates = _getIntermediateStops(
                  stops,
                  oIdx,
                  i,
                  stopIdToStation,
                );

                reachFromOrigin[stm]![rId] = {
                  'wait': wait,
                  'dur': dur == 0 ? 15 : dur,
                  'depart': stops[oIdx]['arrival_time'],
                  'stops': intermediates,
                  'trip': tripId,
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
              int dur =
                  (_timeToMinutes(stops[dIdx]['arrival_time']) -
                          _timeToMinutes(stops[i]['arrival_time']))
                      .abs();
              if (!reachToDest[stm]!.containsKey(rId) ||
                  (dur == 0 ? 15 : dur) < reachToDest[stm]![rId]!['dur']) {
                List<String> intermediates = _getIntermediateStops(
                  stops,
                  i,
                  dIdx,
                  stopIdToStation,
                );

                reachToDest[stm]![rId] = {
                  'dur': dur == 0 ? 15 : dur,
                  'stops': intermediates,
                  'trip': tripId,
                };
              }
            }
          }
        }
      }

      // NOTE: a hardcoded special case for origin names containing 'PV15' or
      // 'COLUMBIA' used to live here, injecting a fake edge to a specific LRT
      // station for the '250'/'T250' routes. Removed: it only masked whatever
      // real gap (missing stop/shape match, wrong stop_id, etc.) made that one
      // route fail to resolve through the general path below. If that route
      // still doesn't resolve after the candidate-station widening in
      // journey_planning.dart, the fix belongs in the GTFS data/matching, not
      // a name check here.

      for (final rId in bestDirect.keys) {
        final m =
            _allRouteMetadata[rId] ??
            {'short_name': rId, 'color': Colors.blue, 'folder': 'bus'};
        final data = bestDirect[rId]!;
        final departStr = (data['depart'] as String).substring(0, 5);
        final List<String> intermediateNames =
            (data['stops'] as List<String>?) ?? [];

        final directFare = _fareForLeg(
          m['folder'],
          _calculateDistance(
            origin.lat,
            origin.lon,
            destination.lat,
            destination.lon,
          ),
        );
        results.add({
          'id': rId,
          'name': m['short_name'],
          'duration': '${data['dur']} min',
          'fare': 'RM ${directFare.toStringAsFixed(2)}',
          'badge': 'Direct',
          'color': m['color'],
          'sig': 'DIR_$rId',
          'wait': data['wait'],
          'scheduledDepart': departStr,
          'legs': [
            {
              'mode': m['folder'] == 'rail' ? 'Rail' : 'Bus',
              'name': m['short_name'],
              'duration': '${data['dur']} min',
              'icon': m['folder'] == 'rail'
                  ? Icons.train
                  : Icons.directions_bus,
              'color': m['color'],
              'desc': 'Board ${m['short_name']} at ${origin.name} ($departStr)',
              'intermediate_stops': intermediateNames,
              'folder': m['folder'],
              'shapeId': _tripToShapeCache[data['trip']] ?? '',
              'from': {'lat': origin.lat, 'lon': origin.lon},
              'to': {'lat': destination.lat, 'lon': destination.lon},
            },
          ],
        });
      }

      for (final stm in reachFromOrigin.keys) {
        if (reachToDest.containsKey(stm)) {
          for (final r1Id in reachFromOrigin[stm]!.keys) {
            for (final r2Id in reachToDest[stm]!.keys) {
              if (r1Id == r2Id) continue;
              final m1 =
                  _allRouteMetadata[r1Id] ??
                  {'short_name': r1Id, 'color': Colors.red, 'folder': 'bus'};
              final m2 =
                  _allRouteMetadata[r2Id] ??
                  {'short_name': r2Id, 'color': Colors.blue, 'folder': 'rail'};

              int walkMins = (m1['folder'] == 'rail' && m2['folder'] == 'rail')
                  ? 3
                  : 5;
              final d1 = reachFromOrigin[stm]![r1Id]!['dur'];
              final d2 = reachToDest[stm]![r2Id]!['dur'];
              final wait = reachFromOrigin[stm]![r1Id]!['wait'];
              final departStr =
                  (reachFromOrigin[stm]![r1Id]!['depart'] as String).substring(
                    0,
                    5,
                  );

              final List<String> iStops1 =
                  (reachFromOrigin[stm]![r1Id]!['stops'] as List<String>?) ??
                  [];
              final List<String> iStops2 =
                  (reachToDest[stm]![r2Id]!['stops'] as List<String>?) ?? [];

              final total = d1 + d2 + walkMins;
              final oneTransferFare =
                  _fareForLeg(
                    m1['folder'],
                    _calculateDistance(
                      origin.lat,
                      origin.lon,
                      stm.lat,
                      stm.lon,
                    ),
                  ) +
                  _fareForLeg(
                    m2['folder'],
                    _calculateDistance(
                      stm.lat,
                      stm.lon,
                      destination.lat,
                      destination.lon,
                    ),
                  );

              results.add({
                'id': 'MIX',
                'name':
                    '${m1['short_name']} -> ${m2['short_name']} (via ${stm.name})',
                'duration': '$total min',
                'fare': 'RM ${oneTransferFare.toStringAsFixed(2)}',
                'badge': '1 Transfer',
                'color': Colors.orange,
                'sig': '1X_${m1['short_name']}_${stm.name}_${m2['short_name']}',
                'wait': wait,
                'scheduledDepart': departStr,
                'legs': [
                  {
                    'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus',
                    'name': m1['short_name'],
                    'duration': '$d1 min',
                    'icon': m1['folder'] == 'rail'
                        ? Icons.train
                        : Icons.directions_bus,
                    'color': m1['color'],
                    'desc':
                        'Board ${m1['short_name']} at ${origin.name} ($departStr)',
                    'intermediate_stops': iStops1,
                    'folder': m1['folder'],
                    'shapeId':
                        _tripToShapeCache[reachFromOrigin[stm]![r1Id]!['trip']] ??
                        '',
                    'from': {'lat': origin.lat, 'lon': origin.lon},
                    'to': {'lat': stm.lat, 'lon': stm.lon},
                  },
                  {
                    'mode': 'Walk',
                    'name': 'Interchange',
                    'duration': '$walkMins min',
                    'icon': Icons.directions_walk,
                    'color': Colors.grey,
                    'desc': 'Transfer at ${stm.name}',
                    'from': {'lat': stm.lat, 'lon': stm.lon},
                    'to': {'lat': stm.lat, 'lon': stm.lon},
                  },
                  {
                    'mode': m2['folder'] == 'rail' ? 'Rail' : 'Bus',
                    'name': m2['short_name'],
                    'duration': '$d2 min',
                    'icon': m2['folder'] == 'rail'
                        ? Icons.train
                        : Icons.directions_bus,
                    'color': m2['color'],
                    'desc':
                        'Board ${m2['short_name']} -> Arrive at ${destination.name}',
                    'intermediate_stops': iStops2,
                    'folder': m2['folder'],
                    'shapeId':
                        _tripToShapeCache[reachToDest[stm]![r2Id]!['trip']] ??
                        '',
                    'from': {'lat': stm.lat, 'lon': stm.lon},
                    'to': {'lat': destination.lat, 'lon': destination.lon},
                  },
                ],
              });
            }
          }
        }
      }

      Map<StationModel, Map<StationModel, Map<String, dynamic>>> railBridges =
          {};
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
            int dur =
                (_timeToMinutes(stops[j]['arrival_time']) -
                        _timeToMinutes(stops[i]['arrival_time']))
                    .abs();
            if (dur == 0) dur = 10;

            railBridges.putIfAbsent(stm1, () => {});
            if (!railBridges[stm1]!.containsKey(stm2) ||
                dur < railBridges[stm1]![stm2]!['dur']) {
              List<String> intermediates = _getIntermediateStops(
                stops,
                i,
                j,
                stopIdToStation,
              );
              railBridges[stm1]![stm2] = {
                'rId': rId,
                'dur': dur,
                'stops': intermediates,
                'trip': tripId,
              };
            }
          }
        }
      }

      for (final stm1 in railBridges.keys) {
        for (final stm2 in railBridges[stm1]!.keys) {
          final bridge = railBridges[stm1]![stm2]!;
          for (final r1Id in reachFromOrigin[stm1]!.keys) {
            for (final r3Id in reachToDest[stm2]!.keys) {
              if (r1Id == bridge['rId'] ||
                  bridge['rId'] == r3Id ||
                  r1Id == r3Id)
                continue;

              final m1 =
                  _allRouteMetadata[r1Id] ??
                  {'short_name': r1Id, 'color': Colors.red, 'folder': 'bus'};
              final m2 =
                  _allRouteMetadata[bridge['rId']] ??
                  {
                    'short_name': bridge['rId'],
                    'color': Colors.blue,
                    'folder': 'rail',
                  };
              final m3 =
                  _allRouteMetadata[r3Id] ??
                  {'short_name': r3Id, 'color': Colors.green, 'folder': 'rail'};

              int walk1 = (m1['folder'] == 'rail') ? 3 : 5;
              int walk2 = (m3['folder'] == 'rail') ? 3 : 5;

              final d1 = reachFromOrigin[stm1]![r1Id]!['dur'];
              final d2 = bridge['dur'];
              final d3 = reachToDest[stm2]![r3Id]!['dur'];
              final wait = reachFromOrigin[stm1]![r1Id]!['wait'];
              final departStr =
                  (reachFromOrigin[stm1]![r1Id]!['depart'] as String).substring(
                    0,
                    5,
                  );

              final List<String> iStops1 =
                  (reachFromOrigin[stm1]![r1Id]!['stops'] as List<String>?) ??
                  [];
              final List<String> iStopsBridge =
                  (bridge['stops'] as List<String>?) ?? [];
              final List<String> iStops3 =
                  (reachToDest[stm2]![r3Id]!['stops'] as List<String>?) ?? [];

              final twoTransferFare =
                  _fareForLeg(
                    m1['folder'],
                    _calculateDistance(
                      origin.lat,
                      origin.lon,
                      stm1.lat,
                      stm1.lon,
                    ),
                  ) +
                  _fareForLeg(
                    m2['folder'],
                    _calculateDistance(stm1.lat, stm1.lon, stm2.lat, stm2.lon),
                  ) +
                  _fareForLeg(
                    m3['folder'],
                    _calculateDistance(
                      stm2.lat,
                      stm2.lon,
                      destination.lat,
                      destination.lon,
                    ),
                  );

              results.add({
                'id': 'MIX2',
                'name':
                    '${m1['short_name']} -> ${m2['short_name']} -> ${m3['short_name']}',
                'duration': '${d1 + d2 + d3 + walk1 + walk2} min',
                'fare': 'RM ${twoTransferFare.toStringAsFixed(2)}',
                'badge': '2 Transfers',
                'color': Colors.purple,
                'sig':
                    '2X_${m1['short_name']}_${stm1.name}_${m2['short_name']}_${stm2.name}_${m3['short_name']}',
                'wait': wait,
                'scheduledDepart': departStr,
                'legs': [
                  {
                    'mode': m1['folder'] == 'rail' ? 'Rail' : 'Bus',
                    'name': m1['short_name'],
                    'duration': '$d1 min',
                    'icon': m1['folder'] == 'rail'
                        ? Icons.train
                        : Icons.directions_bus,
                    'color': m1['color'],
                    'desc': 'Board at ${origin.name} ($departStr)',
                    'intermediate_stops': iStops1,
                    'folder': m1['folder'],
                    'shapeId':
                        _tripToShapeCache[reachFromOrigin[stm1]![r1Id]!['trip']] ??
                        '',
                    'from': {'lat': origin.lat, 'lon': origin.lon},
                    'to': {'lat': stm1.lat, 'lon': stm1.lon},
                  },
                  {
                    'mode': 'Walk',
                    'name': 'Transfer',
                    'duration': '$walk1 min',
                    'icon': Icons.directions_walk,
                    'color': Colors.grey,
                    'desc': 'Transfer at ${stm1.name}',
                    'from': {'lat': stm1.lat, 'lon': stm1.lon},
                    'to': {'lat': stm1.lat, 'lon': stm1.lon},
                  },
                  {
                    'mode': 'Rail',
                    'name': m2['short_name'],
                    'duration': '$d2 min',
                    'icon': Icons.train,
                    'color': m2['color'],
                    'desc': 'Connect via ${stm1.name}',
                    'intermediate_stops': iStopsBridge,
                    'folder': 'rail',
                    'shapeId': _tripToShapeCache[bridge['trip']] ?? '',
                    'from': {'lat': stm1.lat, 'lon': stm1.lon},
                    'to': {'lat': stm2.lat, 'lon': stm2.lon},
                  },
                  {
                    'mode': 'Walk',
                    'name': 'Transfer',
                    'duration': '$walk2 min',
                    'icon': Icons.directions_walk,
                    'color': Colors.grey,
                    'desc': 'Transfer at ${stm2.name}',
                    'from': {'lat': stm2.lat, 'lon': stm2.lon},
                    'to': {'lat': stm2.lat, 'lon': stm2.lon},
                  },
                  {
                    'mode': m3['folder'] == 'rail' ? 'Rail' : 'Bus',
                    'name': m3['short_name'],
                    'duration': '$d3 min',
                    'icon': m3['folder'] == 'rail'
                        ? Icons.train
                        : Icons.directions_bus,
                    'color': m3['color'],
                    'desc': 'Arrive at ${destination.name}',
                    'intermediate_stops': iStops3,
                    'folder': m3['folder'],
                    'shapeId':
                        _tripToShapeCache[reachToDest[stm2]![r3Id]!['trip']] ??
                        '',
                    'from': {'lat': stm2.lat, 'lon': stm2.lon},
                    'to': {'lat': destination.lat, 'lon': destination.lon},
                  },
                ],
              });
            }
          }
        }
      }

      final Map<String, Map<String, dynamic>> uniqueResults = {};
      for (var r in results) {
        if (!uniqueResults.containsKey(r['sig']) ||
            int.parse(r['duration'].split(' ')[0]) <
                int.parse(uniqueResults[r['sig']]!['duration'].split(' ')[0])) {
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

      // Consumers decide how many options to display. Favourite-route replanning
      // must be able to find a saved service sequence even when it is no longer
      // ranked in the current top four results.
      return finalResults;
    } catch (e) {
      debugPrint('Error finding routes: $e');
      return [];
    }
  }

  /// Validates a stable Favourite Route against the same GTFS assets and
  /// station grouping used by Journey Planning.
  Future<RouteServiceAvailability> validateRouteTimetable({
    required StationModel origin,
    required StationModel destination,
    required List<String> serviceSequence,
    required Set<int> weekdays,
    required int departureTimeMinutes,
    DateTime? referenceDate,
  }) async {
    final stations = await loadAllStations();
    final expectedServices = serviceSequence
        .map(_normaliseRouteService)
        .where((service) => service.isNotEmpty)
        .toSet();
    final timetableTrips = <GtfsTimetableTrip>[];

    for (final entry in _allTripStopTimes.entries) {
      final tripId = entry.key;
      final routeId = _tripToRouteCache[tripId];
      final serviceId = _tripToServiceCache[tripId];
      final metadata = routeId == null ? null : _allRouteMetadata[routeId];
      final routeName = metadata?['short_name']?.toString() ?? routeId ?? '';
      if (serviceId == null ||
          !expectedServices.contains(_normaliseRouteService(routeName))) {
        continue;
      }
      final folder =
          metadata?['folder']?.toString() ??
          (tripId.contains('_') ? tripId.split('_').first : 'bus');
      final calls = <GtfsTimetableCall>[];
      for (final stop in entry.value) {
        final arrival = _gtfsTimeSeconds(stop['arrival_time']?.toString());
        final departure = _gtfsTimeSeconds(stop['departure_time']?.toString());
        if (arrival == null || departure == null) continue;
        calls.add(
          GtfsTimetableCall(
            stopId: stop['stop_id'].toString(),
            arrivalSeconds: arrival,
            departureSeconds: departure,
          ),
        );
      }
      if (calls.length < 2) continue;
      timetableTrips.add(
        GtfsTimetableTrip(
          id: tripId,
          folder: folder,
          routeName: routeName,
          serviceId: serviceId,
          calls: calls,
          frequencies: _tripFrequencies[tripId] ?? const [],
        ),
      );
    }

    final stopGroups = <String, String>{};
    for (final station in stations) {
      final ids = station.ids.toList()..sort();
      final group = ids.join('|');
      for (final id in ids) {
        stopGroups[id] = group;
      }
    }
    return const GtfsRouteTimetableValidator().validate(
      trips: timetableTrips,
      calendars: _serviceCalendars,
      stopGroups: stopGroups,
      originStopIds: origin.ids.toSet(),
      destinationStopIds: destination.ids.toSet(),
      serviceSequence: serviceSequence,
      weekdays: weekdays,
      departureTimeMinutes: departureTimeMinutes,
      referenceDate: referenceDate ?? DateTime.now(),
    );
  }

  Map<String, List<GtfsFrequencyWindow>> _parseFrequencies(
    String raw,
    String folder,
  ) {
    final rows = _gtfsRows(raw);
    final result = <String, List<GtfsFrequencyWindow>>{};
    if (rows.isEmpty) return result;
    final header = rows.first;
    final tripIndex = header.indexOf('trip_id');
    final startIndex = header.indexOf('start_time');
    final endIndex = header.indexOf('end_time');
    final headwayIndex = header.indexOf('headway_secs');
    if ([tripIndex, startIndex, endIndex, headwayIndex].contains(-1)) {
      return result;
    }
    for (final row in rows.skip(1)) {
      if (row.length <=
          [
            tripIndex,
            startIndex,
            endIndex,
            headwayIndex,
          ].reduce((first, second) => first > second ? first : second)) {
        continue;
      }
      final start = _gtfsTimeSeconds(row[startIndex]);
      final end = _gtfsTimeSeconds(row[endIndex]);
      final headway = int.tryParse(row[headwayIndex]);
      if (start == null || end == null || headway == null || headway <= 0) {
        continue;
      }
      final tripId = '${folder}_${row[tripIndex]}';
      result
          .putIfAbsent(tripId, () => [])
          .add(
            GtfsFrequencyWindow(
              startSeconds: start,
              endSeconds: end,
              headwaySeconds: headway,
            ),
          );
    }
    return result;
  }

  Map<String, Map<int, bool>> _parseCalendarExceptions(
    String raw,
    String folder,
  ) {
    final rows = _gtfsRows(raw);
    final result = <String, Map<int, bool>>{};
    if (rows.isEmpty) return result;
    final header = rows.first;
    final serviceIndex = header.indexOf('service_id');
    final dateIndex = header.indexOf('date');
    final typeIndex = header.indexOf('exception_type');
    if ([serviceIndex, dateIndex, typeIndex].contains(-1)) return result;
    for (final row in rows.skip(1)) {
      if (row.length <=
          [
            serviceIndex,
            dateIndex,
            typeIndex,
          ].reduce((first, second) => first > second ? first : second)) {
        continue;
      }
      final date = int.tryParse(row[dateIndex]);
      final type = int.tryParse(row[typeIndex]);
      if (date == null || (type != 1 && type != 2)) continue;
      final serviceId = '${folder}_${row[serviceIndex]}';
      result.putIfAbsent(serviceId, () => {})[date] = type == 1;
    }
    return result;
  }

  Map<String, GtfsServiceCalendar> _parseCalendars(String raw, String folder) {
    final rows = _gtfsRows(raw);
    final result = <String, GtfsServiceCalendar>{};
    if (rows.isEmpty) return result;
    final header = rows.first;
    final serviceIndex = header.indexOf('service_id');
    final startIndex = header.indexOf('start_date');
    final endIndex = header.indexOf('end_date');
    const dayNames = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final dayIndexes = dayNames.map(header.indexOf).toList();
    if ([serviceIndex, startIndex, endIndex, ...dayIndexes].contains(-1)) {
      return result;
    }
    for (final row in rows.skip(1)) {
      final largestIndex = [
        serviceIndex,
        startIndex,
        endIndex,
        ...dayIndexes,
      ].reduce((first, second) => first > second ? first : second);
      if (row.length <= largestIndex) continue;
      final start = _gtfsDate(row[startIndex]);
      final end = _gtfsDate(row[endIndex]);
      if (start == null || end == null) continue;
      final serviceId = '${folder}_${row[serviceIndex]}';
      result[serviceId] = GtfsServiceCalendar(
        weekdays: {
          for (var index = 0; index < dayIndexes.length; index++)
            if (row[dayIndexes[index]] == '1') index + 1,
        },
        startDate: start,
        endDate: end,
        exceptions: _calendarExceptions[serviceId] ?? const {},
      );
    }
    return result;
  }

  List<List<String>> _gtfsRows(String raw) =>
      const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
          .convert(raw.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n'))
          .where((row) => row.any((cell) => cell.toString().trim().isNotEmpty))
          .map((row) => row.map((cell) => cell.toString().trim()).toList())
          .toList();

  static int? _gtfsTimeSeconds(String? value) {
    if (value == null) return null;
    final parts = value.trim().split(':');
    if (parts.length != 3) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    final second = int.tryParse(parts[2]);
    if (hour == null ||
        minute == null ||
        second == null ||
        hour < 0 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      return null;
    }
    return hour * 3600 + minute * 60 + second;
  }

  static DateTime? _gtfsDate(String value) {
    if (!RegExp(r'^\d{8}$').hasMatch(value)) return null;
    return DateTime(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
    );
  }

  static String _normaliseRouteService(String value) {
    var result = value
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (result.contains('KELANA JAYA') ||
        result == 'KJ' ||
        result == 'KJL' ||
        result == 'LINE 5') {
      result = 'KELANA JAYA';
    }
    return result;
  }

  Map<String, Map<String, dynamic>> _parseRouteMetadata(
    String raw,
    String folder,
  ) {
    final lines = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(raw.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n'))
        .where((row) => row.any((cell) => cell.toString().trim().isNotEmpty))
        .toList();
    final Map<String, Map<String, dynamic>> metadata = {};
    if (lines.isEmpty) return metadata;

    final header = lines[0].map((e) => e.toString().trim()).toList();
    final idIdx = header.indexOf('route_id');
    final shortNameIdx = header.indexOf('route_short_name');
    final longNameIdx = header.indexOf('route_long_name');
    final colorIdx = header.indexOf('route_color');

    for (final line in lines.skip(1)) {
      final parts = line.map((e) => e.toString().trim()).toList();
      if (idIdx == -1 || idIdx >= parts.length) continue;

      final routeId = '${folder}_${parts[idIdx]}';

      String routeShortName = '';
      if (shortNameIdx != -1 &&
          parts.length > shortNameIdx &&
          parts[shortNameIdx].trim().isNotEmpty) {
        routeShortName = parts[shortNameIdx].trim();
      }
      if (routeShortName.isEmpty &&
          longNameIdx != -1 &&
          parts.length > longNameIdx &&
          parts[longNameIdx].trim().isNotEmpty) {
        routeShortName = parts[longNameIdx].trim();
      }

      String effectiveFolder = folder;

      if (routeShortName.contains('BRT') ||
          routeShortName.contains('SBL') ||
          routeId.contains('SBL')) {
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

      String routeColorHex = colorIdx != -1 && parts.length > colorIdx
          ? parts[colorIdx]
          : '';

      if (effectiveFolder == 'rail') {
        if (routeShortName.contains('Kelana Jaya') ||
            routeShortName == 'KJL' ||
            routeId.contains('KJL')) {
          routeShortName = 'Line 5 (Kelana Jaya)';
          routeColorHex = 'E11D48';
        } else if (routeShortName.contains('Kajang') ||
            routeShortName == 'KGL' ||
            routeId.contains('KGL') ||
            routeId.contains('SBK')) {
          routeShortName = 'Line 9 (Kajang)';
          routeColorHex = '15803D';
        } else if (routeShortName.contains('Putrajaya') ||
            routeShortName == 'PYL' ||
            routeId.contains('PYL') ||
            routeId.contains('SSP')) {
          routeShortName = 'Line 12 (Putrajaya)';
          routeColorHex = 'EAB308';
        } else if (routeShortName.contains('Ampang') ||
            routeShortName == 'AGL' ||
            routeId.contains('AGL')) {
          routeShortName = 'Line 3 (Ampang)';
          routeColorHex = 'F97316';
        } else if (routeShortName.contains('Sri Petaling') ||
            routeShortName == 'SPL' ||
            routeId.contains('SPL')) {
          routeShortName = 'Line 4 (Sri Petaling)';
          routeColorHex = '7F1D1D';
        } else if (routeShortName.contains('Monorail') ||
            routeShortName == 'MRL' ||
            routeId.contains('MRL')) {
          routeShortName = 'Line 8 (Monorail)';
          routeColorHex = '84CC16';
        } else if (routeShortName.contains('Sunway') ||
            routeShortName.contains('BRT')) {
          routeShortName = 'B1 (BRT Sunway)';
          routeColorHex = '14532D';
        } else if (routeShortName.contains('Seremban') ||
            routeShortName == 'KTM Seremban') {
          routeShortName = 'Line 1 (Seremban)';
          routeColorHex = '2563EB';
        } else if (routeShortName.contains('Port Klang') ||
            routeShortName.contains('Pelabuhan')) {
          routeShortName = 'Line 2 (Port Klang)';
          routeColorHex = 'DC2626';
        }
      }

      if (routeColorHex.isEmpty || routeColorHex.length != 6) {
        routeColorHex = effectiveFolder == 'rail' ? '2563EB' : '9CA3AF';
      }

      metadata[routeId] = {
        'short_name': routeShortName,
        'color': Color(int.parse('0xFF$routeColorHex')),
        'folder': effectiveFolder,
      };
    }
    return metadata;
  }

  Map<String, String> _parseTrips(String raw, String folder) {
    final lines = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(raw.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n'))
        .where((row) => row.any((cell) => cell.toString().trim().isNotEmpty))
        .toList();
    final Map<String, String> tripToRoute = {};
    if (lines.isEmpty) return tripToRoute;
    final header = lines[0].map((e) => e.toString().trim()).toList();
    final routeIdIdx = header.indexOf('route_id');
    final tripIdIdx = header.indexOf('trip_id');
    final serviceIdIdx = header.indexOf('service_id');
    final shapeIdIdx = header.indexOf('shape_id');
    if (routeIdIdx == -1 || tripIdIdx == -1) return tripToRoute;

    for (final line in lines.skip(1)) {
      final parts = line.map((e) => e.toString().trim()).toList();
      if (parts.length > tripIdIdx && parts.length > routeIdIdx) {
        final tripId = '${folder}_${parts[tripIdIdx]}';
        tripToRoute[tripId] = '${folder}_${parts[routeIdIdx]}';
        if (serviceIdIdx != -1 && parts.length > serviceIdIdx) {
          _tripToServiceCache[tripId] =
              '${folder}_${parts[serviceIdIdx].trim()}';
        }
        if (shapeIdIdx != -1 &&
            parts.length > shapeIdIdx &&
            parts[shapeIdIdx].trim().isNotEmpty) {
          _tripToShapeCache[tripId] = parts[shapeIdIdx].trim();
        }
      }
    }
    return tripToRoute;
  }

  Map<String, List<Map<String, dynamic>>> _parseStopTimes(
    String raw,
    Map<String, String> tripToRoute,
    String folder,
  ) {
    final lines = const CsvToListConverter(eol: '\n', shouldParseNumbers: false)
        .convert(raw.replaceAll('\uFEFF', '').replaceAll('\r\n', '\n'))
        .where((row) => row.any((cell) => cell.toString().trim().isNotEmpty))
        .toList();
    final Map<String, List<Map<String, dynamic>>> tripStopTimes = {};
    if (lines.isEmpty) return tripStopTimes;

    final header = lines[0].map((e) => e.toString().trim()).toList();
    final tripIdIdx = header.indexOf('trip_id');
    final stopIdIdx = header.indexOf('stop_id');
    final arrivalTimeIdx = header.indexOf('arrival_time');
    final departureTimeIdx = header.indexOf('departure_time');
    final seqIdx = header.indexOf('stop_sequence');

    if (tripIdIdx == -1 || stopIdIdx == -1 || arrivalTimeIdx == -1)
      return tripStopTimes;

    for (final line in lines.skip(1)) {
      final parts = line.map((e) => e.toString().trim()).toList();
      if (parts.length > stopIdIdx &&
          parts.length > arrivalTimeIdx &&
          parts.length > tripIdIdx) {
        final tripId = '${folder}_${parts[tripIdIdx]}';
        final seq = seqIdx != -1 && parts.length > seqIdx
            ? int.tryParse(parts[seqIdx]) ?? 0
            : 0;

        if (!tripStopTimes.containsKey(tripId)) tripStopTimes[tripId] = [];

        tripStopTimes[tripId]!.add({
          'stop_id': '${folder}_${parts[stopIdIdx]}',
          'arrival_time': parts[arrivalTimeIdx],
          'departure_time':
              departureTimeIdx != -1 && parts.length > departureTimeIdx
              ? parts[departureTimeIdx]
              : parts[arrivalTimeIdx],
          'route_id': tripToRoute[tripId] ?? tripId,
          'seq': seq,
        });
      }
    }

    for (final tripId in tripStopTimes.keys) {
      tripStopTimes[tripId]!.sort(
        (a, b) => (a['seq'] as int).compareTo(b['seq'] as int),
      );
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
      if (user == null)
        throw Exception('User is not logged in. Please log in first.');

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
            'origin_station': originStation == null
                ? null
                : {
                    'ids': originStation.ids.toList()..sort(),
                    'name': originStation.name,
                    'lines': originStation.lines.toList()..sort(),
                    'category': originStation.category,
                    'lat': originStation.lat,
                    'lon': originStation.lon,
                  },
            'destination_station': destinationStation == null
                ? null
                : {
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
          },
        },
      );
    } catch (e) {
      throw Exception('Failed to save navigation to database: ${e.toString()}');
    }
  }

  Future<List<LiveVehicle>> getLiveVehicles(String folder) async {
    folder = folder.trim().toLowerCase();
    if (folder == 'mrtfeeder' || folder == 'rapid-bus-mrtfeeder') {
      folder = 'mrt_feeder';
    }
    if (folder == 'rapid-bus-kl') folder = 'bus';
    // KTMB is explicitly excluded, including direct calls from other screens.
    if (folder == 'ktmb' || folder == 'ktm') return [];
    if (folder == 'rail' || folder == 'rapid-rail-kl') {
      debugPrint(
        'LRT live positions unavailable: the MyRapid bus kiosk '
        'provides bus GPS and static endpoint areas, not train positions.',
      );
      return [];
    }
    if (folder != 'bus' && folder != 'mrt_feeder') {
      throw ArgumentError.value(folder, 'folder', 'Unsupported live feed');
    }
    final category = folder == 'mrt_feeder'
        ? 'rapid-bus-mrtfeeder'
        : 'rapid-bus-kl';
    try {
      await _ensureGtfsFullyCached();
      final response = await http
          .get(
            Uri.parse(
              'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=$category',
            ),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        debugPrint('GTFS-RT $folder: HTTP ${response.statusCode}');
        return [];
      }
      final feed = gtfs.FeedMessage.fromBuffer(response.bodyBytes);
      final vehicles = <LiveVehicle>[];
      for (final entity in feed.entity) {
        if (!entity.hasVehicle()) continue;
        final v = entity.vehicle;
        if (!v.hasPosition()) continue;
        final lat = v.position.latitude;
        final lon = v.position.longitude;
        if (!lat.isFinite ||
            !lon.isFinite ||
            lat.abs() > 90 ||
            lon.abs() > 180 ||
            (lat == 0 && lon == 0))
          continue;
        final rawRoute = v.trip.routeId.trim();
        final rawTrip = v.trip.tripId.trim();
        String? resolved;

        // IDs belong to their source feed. Never guess using digits or plates.
        final routeKey = '${folder}_$rawRoute';
        if (rawRoute.isNotEmpty && _allRouteMetadata.containsKey(routeKey)) {
          resolved = routeKey;
        }
        if (resolved == null && rawRoute.isNotEmpty) {
          final matches = _allRouteMetadata.entries
              .where(
                (entry) =>
                    entry.key.startsWith('${folder}_') &&
                    entry.value['short_name'].toString().trim().toUpperCase() ==
                        rawRoute.toUpperCase(),
              )
              .map((entry) => entry.key)
              .toSet();
          if (matches.length == 1) resolved = matches.single;
        }
        if (resolved == null && rawTrip.isNotEmpty) {
          resolved = _tripToRouteCache['${folder}_$rawTrip'];
          if (resolved == null) {
            // Some feeds omit the static service prefix. Accept only an
            // underscore-delimited suffix that resolves to one route.
            final matches = _tripToRouteCache.entries
                .where(
                  (entry) =>
                      entry.key.startsWith('${folder}_') &&
                      entry.key
                          .substring(folder.length + 1)
                          .endsWith('_$rawTrip'),
                )
                .map((entry) => entry.value)
                .toSet();
            if (matches.length == 1) resolved = matches.single;
          }
        }
        final routeName = resolved == null
            ? (rawRoute.isEmpty ? 'Unknown route' : rawRoute)
            : _allRouteMetadata[resolved]?['short_name']?.toString() ??
                  rawRoute;
        vehicles.add(
          LiveVehicle(
            id: '${folder}_${entity.id}',
            lat: lat,
            lon: lon,
            bearing: v.position.hasBearing() && v.position.bearing.isFinite
                ? v.position.bearing
                : 0.0,
            routeId: routeName,
            licensePlate: v.vehicle.hasLicensePlate()
                ? v.vehicle.licensePlate
                : 'Unknown',
          ),
        );
      }
      debugPrint('GTFS-RT $folder: ${vehicles.length} vehicles');
      return vehicles;
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
        records.add(
          RidershipRecord(
            origin: row['origin'] as String,
            destination: row['destination'] as String,
            date: DateTime.parse(row['date'] as String),
            ridership: (row['ridership'] as num).round(),
          ),
        );
      } catch (_) {
        continue;
      }
    }
    _stationRecordsCache[station] = records;
    return records;
  }

  Future<List<MapEntry<DateTime, int>>> getDailyTotalsForStation(
    String station,
  ) async {
    final records = await getStationTotalRecords(station);
    return records.map((r) => MapEntry(r.date, r.ridership)).toList();
  }

  Future<double> getStationAverageRidership(String station) async {
    final records = await getStationTotalRecords(station);
    if (records.isEmpty) return 0;
    final total = records.fold<int>(0, (sum, r) => sum + r.ridership);
    return total / records.length;
  }

  Future<double> getStationAverageForWeekday(
    String station,
    int weekday,
  ) async {
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

  Future<
    List<
      ({
        String station,
        double avgRidership,
        int totalRidership,
        int recordCount,
        DateTime? minDate,
        DateTime? maxDate,
      })
    >
  >
  getStationRidershipTotals({
    DateTime? startDate,
    DateTime? endDate,
    bool forceRefresh = false,
  }) async {
    final isOverall = startDate == null && endDate == null;
    if (isOverall && !forceRefresh && _stationRidershipTotalsCache != null) {
      return _stationRidershipTotalsCache!;
    }

    final List<Map<String, dynamic>> rows;
    if (isOverall) {
      rows = await Supabase.instance.client
          .from('station_ridership_totals')
          .select(
            'station, avg_ridership, total_ridership, record_count, min_date, max_date',
          )
          .order('avg_ridership', ascending: false);
    } else {
      rows = await Supabase.instance.client.rpc(
        'station_ridership_totals_for_range',
        params: {
          'start_date': DateFormat('yyyy-MM-dd').format(startDate!),
          'end_date': DateFormat('yyyy-MM-dd').format(endDate!),
        },
      );
    }

    final results = rows
        .map(
          (row) => (
            station: row['station'] as String,
            avgRidership: (row['avg_ridership'] as num).toDouble(),
            totalRidership: (row['total_ridership'] as num).round(),
            recordCount: (row['record_count'] as num).round(),
            minDate: row['min_date'] != null
                ? DateTime.tryParse(row['min_date'] as String)
                : null,
            maxDate: row['max_date'] != null
                ? DateTime.tryParse(row['max_date'] as String)
                : null,
          ),
        )
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
    String station, {
    int limit = 5,
  }) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('destination, total_ridership')
        .eq('origin', station)
        .order('total_ridership', ascending: false)
        .limit(limit);
    return response
        .map(
          (row) => MapEntry(
            row['destination'] as String,
            (row['total_ridership'] as num).round(),
          ),
        )
        .toList();
  }

  Future<List<MapEntry<String, int>>> getTopOriginsInto(
    String station, {
    int limit = 5,
  }) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('origin, total_ridership')
        .eq('destination', station)
        .order('total_ridership', ascending: false)
        .limit(limit);
    return response
        .map(
          (row) => MapEntry(
            row['origin'] as String,
            (row['total_ridership'] as num).round(),
          ),
        )
        .toList();
  }

  Future<int> getTotalOutgoing(String station) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('total_ridership')
        .eq('origin', station);
    return response.fold<int>(
      0,
      (sum, row) => sum + (row['total_ridership'] as num).round(),
    );
  }

  Future<int> getTotalIncoming(String station) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('total_ridership')
        .eq('destination', station);
    return response.fold<int>(
      0,
      (sum, row) => sum + (row['total_ridership'] as num).round(),
    );
  }

  Future<List<MapEntry<String, int>>> getBusiestConnections({
    int limit = 10,
  }) async {
    final response = await Supabase.instance.client
        .from('od_totals')
        .select('origin, destination, total_ridership')
        .order('total_ridership', ascending: false)
        .limit(limit);
    return response
        .map(
          (row) => MapEntry(
            '${row['origin']} → ${row['destination']}',
            (row['total_ridership'] as num).round(),
          ),
        )
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
      final response = await http.get(
        Uri.parse(
          'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl',
        ),
      );
      if (response.statusCode == 200) {
        return 'Connected: Received ${response.bodyBytes.length} bytes of live data';
      }
      return 'Failed to load live data';
    } catch (e) {
      return 'API Connection Error';
    }
  }
}
