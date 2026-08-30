import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';

// =========================================================
// YOUR CODE (Module 1 / Journey Planning)
// =========================================================
class StationModel {
  final String id;
  final String name;
  final Set<String> lines;
  final String category;

  StationModel({
    required this.id,
    required this.name,
    required this.lines,
    required this.category,
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
  // --- FRIEND'S VARIABLES ---[cite: 1]
  List<RidershipRecord>? _cache;



  // =========================================================
  // YOUR METHODS (Module 1 / Journey Planning)
  // =========================================================

  Future<List<StationModel>> loadAllStations() async {
    final parsedStations = <StationModel>[];
    final Set<String> seenNames = {};

    // List all three of your GTFS folder paths
    final filePaths = [
      'assets/gtfs/rail/stops.txt',
      'assets/gtfs/mrt_feeder/stops.txt',
      'assets/gtfs/bus/stops.txt',
    ];

    for (String path in filePaths) {
      try {
        final String raw = await rootBundle.loadString(path);
        List<List<dynamic>> csvTable = const CsvToListConverter(eol: '\n').convert(raw);

        if (csvTable.isEmpty) continue;

        final header = csvTable[0].map((e) => e.toString().trim()).toList();
        final idIndex = header.indexOf('stop_id');
        final nameIndex = header.indexOf('stop_name');

        if (idIndex == -1 || nameIndex == -1) continue;

        // Determine category based on the folder name
        String category = 'Bus';
        if (path.contains('rail')) category = 'Rail';
        if (path.contains('mrt_feeder')) category = 'MRT Feeder';

        for (int i = 1; i < csvTable.length; i++) {
          final row = csvTable[i];
          if (row.length > nameIndex) {
            final stopId = row[idIndex].toString().trim();
            final stopName = row[nameIndex].toString().trim();

            // Infer the line based on prefix, or default to the category
            String inferredLine = category;
            if (stopId.startsWith('KJ')) inferredLine = 'Kelana Jaya';
            else if (stopId.startsWith('KG')) inferredLine = 'Kajang';
            else if (stopId.startsWith('AG')) inferredLine = 'Ampang';
            else if (stopId.startsWith('PY')) inferredLine = 'Putrajaya';
            else if (stopId.startsWith('MR')) inferredLine = 'Monorail';
            else if (stopId.startsWith('SP')) inferredLine = 'Sri Petaling';
            else if (stopId.startsWith('KT')) inferredLine = 'KTM';

            // Filter out duplicate station/stop names
            if (!seenNames.contains(stopName)) {
              seenNames.add(stopName);
              parsedStations.add(StationModel(
                id: stopId,
                name: stopName,
                lines: {inferredLine},
                category: category,
              ));
            }
          }
        }
      } catch (e) {
        debugPrint('Failed to load $path: $e');
      }
    }

    // Sort alphabetically at the very end
    parsedStations.sort((a, b) => a.name.compareTo(b.name));
    return parsedStations;
  }

  // =========================================================
  // LOAD ROUTES FROM GTFS ASSETS
  // =========================================================
  Future<List<Map<String, dynamic>>> loadGtfsRoutes() async {
    try {
      // Load the actual routes.txt file from your rail folder
      final String raw = await rootBundle.loadString('assets/gtfs/rail/routes.txt');
      final lines = raw.split('\n').where((l) => l.trim().isNotEmpty).toList();

      final parsedRoutes = <Map<String, dynamic>>[];

      // Skip the first line (the CSV header)
      for (final line in lines.skip(1)) {
        // GTFS files are comma-separated
        final parts = line.split(',');
        if (parts.length < 3) continue;

        // Extracting data based on standard GTFS format
        final routeId = parts[0].trim().replaceAll('"', '');
        final routeName = parts[2].trim().replaceAll('"', ''); // route_long_name

        // Extract color if it exists in the file (usually at index 7)
        final routeColorHex = parts.length > 7 ? parts[7].trim().replaceAll('"', '') : '';
        Color routeColor = const Color(0xFF1E3A8A); // Default fallback color

        if (routeColorHex.isNotEmpty) {
          try {
            // Convert GTFS hex string (e.g. "E02B20") to Flutter Color
            routeColor = Color(int.parse('0xFF$routeColorHex'));
          } catch (_) {}
        }

        parsedRoutes.add({
          'id': routeId,
          'name': routeName,
          'duration': 'Est. 25 min',    // Placeholder: Requires routing engine
          'fare': 'Standard Fare',      // Placeholder: Requires fare_attributes.txt
          'walk': 'To platform',
          'badge': 'Rail',
          'badgeIcon': Icons.train,
          'badgeColor': Colors.blueGrey,
          'color': routeColor,
        });
      }
      return parsedRoutes;
    } catch (e) {
      // If the file fails to load, return an empty list
      return [];
    }
  }


  // =========================================================
  // FRIEND'S METHODS (Untouched)
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