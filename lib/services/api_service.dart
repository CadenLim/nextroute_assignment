import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;

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
  // --- FRIEND'S VARIABLES ---
  List<RidershipRecord>? _cache;

  // =========================================================
  // YOUR METHODS (Module 1 / Journey Planning)
  // =========================================================

  // 👇 MOVED THIS INSIDE THE CLASS! 👇
  Future<List<StationModel>> loadAllStations() async {
    // TODO: You will eventually write your code here to read the GTFS stops.txt files.
    // For now, we are returning a mock list so your app can compile and run without errors!

    // Simulating a brief network/loading delay
    await Future.delayed(const Duration(milliseconds: 500));

    return [
      StationModel(
        id: 'KJ15',
        name: 'KL Sentral',
        lines: {'Kelana Jaya Line'},
        category: 'Rail',
      ),
      StationModel(
        id: 'KG16',
        name: 'Pasar Seni',
        lines: {'Kelana Jaya Line', 'MRT Kajang Line'},
        category: 'Rail',
      ),
      StationModel(
        id: 'AG8',
        name: 'Masjid Jamek',
        lines: {'Ampang Line', 'Kelana Jaya Line'},
        category: 'Rail',
      ),
    ];
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