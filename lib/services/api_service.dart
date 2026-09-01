import 'package:http/http.dart' as http;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  // Small, targeted caches — never the whole 3.9M-row table, and never
  // the whole 16K-row od_totals view either.
  final Map<String, List<RidershipRecord>> _stationRecordsCache = {};
  List<String>? _stationListCache;
  List<String>? _odOriginsCache; // from the tiny od_origins view (~146 rows)
  double? _networkAverageCache;

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

  // ---------------------------------------------------------------------
  // NOTE ON SCALE: the "ridership" table has ~3.9 MILLION rows. Pulling
  // the whole table into the app and filtering client-side (the earlier
  // approach) does not scale to this size — instead:
  //   - Per-station queries below fetch only ~236 rows at a time (one
  //     station's real daily history), not the whole table.
  //   - Three lightweight Postgres VIEWS (station_list, od_totals,
  //     network_average) do the heavy GROUP BY / SUM / AVG work inside
  //     the database, so the app only ever downloads small,
  //     already-aggregated result sets. See the SQL that creates these
  //     views in the project notes / README.
  // ---------------------------------------------------------------------

  static const String kAllStationsCode = 'A0: All Stations';

  // Every real station — from the small "station_list" view, not the
  // raw table.
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
  // rows). At this size we NEVER load the whole view into the app — every
  // method below sends a targeted query (filter by origin/destination,
  // sort, limit) and lets Postgres do the work, so the client only ever
  // receives a handful of rows per action. Deliberately kept to simple
  // filter/sort logic: no path-finding, no multi-hop routes, no fare/ETA
  // — that's Module 1's job. This only answers "how many people
  // travelled between two named stations", never "how do I get from A to B".
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
  // station's own rows (one origin has at most ~114 destination rows,
  // never the whole view), sums them client-side.
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
        .map((row) => MapEntry('${row['origin']} \u2192 ${row['destination']}', (row['total_ridership'] as num).round()))
        .toList();
  }

  // Simple status line shown at the top of the AI Crowd screen.
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