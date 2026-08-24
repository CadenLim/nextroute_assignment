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

    // First line is the header (date,origin,destination,ridership) — skip it.
    final records = <RidershipRecord>[];
    for (final line in lines.skip(1)) {
      final parts = line.split(',');
      if (parts.length < 4) continue; // skip malformed rows instead of crashing
      try {
        records.add(RidershipRecord(
          date: DateTime.parse(parts[0].trim()),
          origin: parts[1].trim(),
          destination: parts[2].trim(),
          ridership: int.parse(parts[3].trim()),
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

  // All records where the given station is either the origin or the
  // destination — this is "how much ridership touched this station".
  Future<List<RidershipRecord>> getRecordsForStation(String station) async {
    final all = await loadRidership();
    return all
        .where((r) => r.origin == station || r.destination == station)
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  // Groups a station's records by date and sums ridership per day.
  // Returns a list sorted chronologically: [(date, totalRidership), ...]
  Future<List<MapEntry<DateTime, int>>> getDailyTotalsForStation(
      String station) async {
    final records = await getRecordsForStation(station);
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
