import 'dart:async';

import 'package:csv/csv.dart';
import 'package:flutter/services.dart';
import 'package:gtfs_realtime_bindings/gtfs_realtime_bindings.dart' as gtfs;
import 'package:http/http.dart' as http;
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class GtfsRealtimeService {
  GtfsRealtimeService({
    http.Client? client,
    List<Uri>? endpoints,
    this.requestTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _endpoints = List.unmodifiable(endpoints ?? [endpoint]);

  static final Uri endpoint = Uri.parse(
    'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-kl',
  );
  static final List<Uri> kualaLumpurBusEndpoints = List.unmodifiable([
    endpoint,
    Uri.parse(
      'https://api.data.gov.my/gtfs-realtime/vehicle-position/prasarana?category=rapid-bus-mrtfeeder',
    ),
  ]);

  final http.Client _client;
  final bool _ownsClient;
  final List<Uri> _endpoints;
  final Duration requestTimeout;

  Future<VehiclePositionFeed> fetchVehiclePositions() async {
    final attempts = await Future.wait(
      _endpoints.map((endpoint) async {
        final category = _categoryForEndpoint(endpoint);
        try {
          return (
            category: category,
            feed: await _fetchEndpoint(endpoint, category),
            error: null,
          );
        } on GtfsRealtimeException catch (error) {
          return (category: category, feed: null, error: error);
        }
      }),
    );
    final feeds = attempts
        .map((attempt) => attempt.feed)
        .whereType<VehiclePositionFeed>();
    if (feeds.isEmpty) {
      throw attempts.first.error ??
          const GtfsRealtimeException(
            'No configured government realtime feed could be read.',
          );
    }
    return VehiclePositionFeed(
      totalEntities: feeds.fold(0, (total, feed) => total + feed.totalEntities),
      vehicles: List.unmodifiable(feeds.expand((feed) => feed.vehicles)),
      sources: List.unmodifiable([
        for (final attempt in attempts)
          if (attempt.feed != null)
            ...attempt.feed!.sources
          else
            RealtimeFeedStatus(
              category: attempt.category,
              availability: RealtimeFeedAvailability.unavailable,
              entityCount: null,
              vehicleCount: null,
              error: attempt.error?.message,
            ),
      ]),
    );
  }

  Future<VehiclePositionFeed> _fetchEndpoint(
    Uri endpoint,
    String category,
  ) async {
    try {
      final response = await _client.get(endpoint).timeout(requestTimeout);
      if (response.statusCode == 429) {
        throw const GtfsRealtimeException(
          'Realtime data is temporarily unavailable because the data service '
          'is receiving too many requests. Please wait and try again.',
        );
      }
      if (response.statusCode != 200) {
        throw GtfsRealtimeException(
          'Government realtime feed returned HTTP ${response.statusCode}.',
        );
      }
      if (response.bodyBytes.isEmpty) {
        throw const GtfsRealtimeException(
          'Government realtime feed returned an empty response.',
        );
      }

      final feedMessage = gtfs.FeedMessage.fromBuffer(response.bodyBytes);
      if (!feedMessage.isInitialized()) {
        throw const GtfsRealtimeException(
          'Government realtime feed contained incomplete protobuf data.',
        );
      }

      final vehicles = <RealtimeVehicle>[];
      for (final entity in feedMessage.entity) {
        if (!entity.hasVehicle() || !entity.vehicle.hasPosition()) {
          continue;
        }

        final vehicle = entity.vehicle;
        final position = vehicle.position;
        if (!position.hasLatitude() || !position.hasLongitude()) {
          continue;
        }
        final latitude = position.latitude;
        final longitude = position.longitude;
        if (!latitude.isFinite ||
            !longitude.isFinite ||
            latitude < -90 ||
            latitude > 90 ||
            longitude < -180 ||
            longitude > 180) {
          continue;
        }

        vehicles.add(
          RealtimeVehicle(
            routeId: vehicle.hasTrip()
                ? _optionalString(
                    vehicle.trip.hasRouteId(),
                    vehicle.trip.routeId,
                  )
                : null,
            timestamp: _decodeTimestamp(vehicle),
            congestionLevel: _decodeCongestionLevel(vehicle),
            sourceCategory: category,
            vehicleId: vehicle.hasVehicle()
                ? _optionalString(
                        vehicle.vehicle.hasId(),
                        vehicle.vehicle.id,
                      ) ??
                      _optionalString(
                        vehicle.vehicle.hasLabel(),
                        vehicle.vehicle.label,
                      )
                : null,
            tripId: vehicle.hasTrip()
                ? _optionalString(vehicle.trip.hasTripId(), vehicle.trip.tripId)
                : null,
          ),
        );
      }

      DateTime? latestUpdate;
      for (final vehicle in vehicles) {
        final timestamp = vehicle.timestamp;
        if (timestamp != null &&
            (latestUpdate == null || timestamp.isAfter(latestUpdate))) {
          latestUpdate = timestamp;
        }
      }
      final now = DateTime.now().toUtc();
      final stale =
          latestUpdate == null ||
          now.difference(latestUpdate).abs() > const Duration(minutes: 5);

      return VehiclePositionFeed(
        totalEntities: feedMessage.entity.length,
        vehicles: List.unmodifiable(vehicles),
        sources: [
          RealtimeFeedStatus(
            category: category,
            availability: vehicles.isEmpty
                ? RealtimeFeedAvailability.noVehicleData
                : stale
                ? RealtimeFeedAvailability.stale
                : RealtimeFeedAvailability.live,
            entityCount: feedMessage.entity.length,
            vehicleCount: vehicles.length,
            latestUpdate: latestUpdate,
          ),
        ],
      );
    } on TimeoutException {
      throw GtfsRealtimeException(
        'Government realtime feed did not respond within '
        '${requestTimeout.inSeconds} seconds.',
      );
    } on http.ClientException catch (error) {
      throw GtfsRealtimeException(
        'Could not connect to the government realtime feed.',
        cause: error,
      );
    } on GtfsRealtimeException {
      rethrow;
    } catch (error) {
      throw GtfsRealtimeException(
        'Could not process the GTFS-Realtime response.',
        cause: error,
      );
    }
  }

  void close() {
    if (_ownsClient) {
      _client.close();
    }
  }

  static String? _optionalString(bool isPresent, String value) {
    if (!isPresent) {
      return null;
    }
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String _categoryForEndpoint(Uri endpoint) =>
      endpoint.queryParameters['category'] ?? endpoint.pathSegments.last;

  static DateTime? _decodeTimestamp(gtfs.VehiclePosition vehicle) {
    if (!vehicle.hasTimestamp()) {
      return null;
    }
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        vehicle.timestamp.toInt() * 1000,
        isUtc: true,
      );
    } on ArgumentError {
      return null;
    }
  }

  static TransitCongestionLevel _decodeCongestionLevel(
    gtfs.VehiclePosition vehicle,
  ) {
    if (!vehicle.hasCongestionLevel()) {
      return TransitCongestionLevel.unknown;
    }
    return switch (vehicle.congestionLevel.value) {
      1 => TransitCongestionLevel.smooth,
      2 => TransitCongestionLevel.stopAndGo,
      3 => TransitCongestionLevel.congested,
      4 => TransitCongestionLevel.severe,
      _ => TransitCongestionLevel.unknown,
    };
  }
}

class GtfsRealtimeException implements Exception {
  const GtfsRealtimeException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

class ServiceAnalyticsCalculator {
  const ServiceAnalyticsCalculator();

  ServiceAnalytics calculate(VehiclePositionFeed feed) {
    final routeCounts = <String, int>{};
    final latestUpdateByRoute = <String, DateTime>{};
    DateTime? latestUpdate;
    var congestedVehicleCount = 0;
    var severeCongestionCount = 0;
    var congestionReportedVehicleCount = 0;

    for (final vehicle in feed.vehicles) {
      if (vehicle.congestionLevel != TransitCongestionLevel.unknown) {
        congestionReportedVehicleCount++;
      }
      final routeId = vehicle.routeId;
      if (routeId != null && routeId.isNotEmpty) {
        routeCounts.update(routeId, (count) => count + 1, ifAbsent: () => 1);
        final timestamp = vehicle.timestamp;
        final previous = latestUpdateByRoute[routeId];
        if (timestamp != null &&
            (previous == null || timestamp.isAfter(previous))) {
          latestUpdateByRoute[routeId] = timestamp;
        }
      }
      if (vehicle.congestionLevel == TransitCongestionLevel.congested) {
        congestedVehicleCount += 1;
      } else if (vehicle.congestionLevel == TransitCongestionLevel.severe) {
        congestedVehicleCount += 1;
        severeCongestionCount += 1;
      }

      final timestamp = vehicle.timestamp;
      if (timestamp != null &&
          (latestUpdate == null || timestamp.isAfter(latestUpdate))) {
        latestUpdate = timestamp;
      }
    }

    final sortedRoutes = routeCounts.entries.toList()
      ..sort((first, second) {
        final countComparison = second.value.compareTo(first.value);
        return countComparison != 0
            ? countComparison
            : first.key.compareTo(second.key);
      });

    final vehiclesByRoute = <String, int>{
      for (final route in sortedRoutes) route.key: route.value,
    };
    return ServiceAnalytics(
      vehicleCount: feed.vehicles.length,
      routeCount: vehiclesByRoute.length,
      vehiclesByRoute: Map.unmodifiable(vehiclesByRoute),
      latestUpdate: latestUpdate,
      congestedVehicleCount: congestedVehicleCount,
      severeCongestionCount: severeCongestionCount,
      congestionReportedVehicleCount: congestionReportedVehicleCount,
      sourceStatuses: feed.sources,
      latestUpdateByRoute: Map.unmodifiable(latestUpdateByRoute),
    );
  }
}

class SupabaseAnalyticsRepository {
  SupabaseAnalyticsRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<DailyAnalyticsSummary>> loadLastSevenDays({DateTime? now}) =>
      loadSummaries(
        start: AnalyticsPeriod.day(
          now ?? DateTime.now(),
        ).subtract(const Duration(days: 6)),
        end: AnalyticsPeriod.day(
          now ?? DateTime.now(),
        ).add(const Duration(days: 1)),
      );

  Future<List<DailyAnalyticsSummary>> loadSummaries({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final rows = await _client.rpc(
        'module5_daily_summaries',
        params: {'start_day': _dateOnly(start), 'end_day': _dateOnly(end)},
      );
      return List.unmodifiable(
        (rows as List).map(
          (row) => DailyAnalyticsSummary.fromSupabase(
            Map<String, dynamic>.from(row as Map),
          ),
        ),
      );
    } on PostgrestException catch (error) {
      // Safe transition before the additive migration has been deployed.
      // Do not mask permission/network errors with an apparently empty report.
      if (error.code != 'PGRST202' && error.code != '42883') rethrow;
      final rows = await _client
          .from('analytics_daily_summary')
          .select()
          .gte('service_date', _dateOnly(start))
          .lt('service_date', _dateOnly(end))
          .order('service_date');
      return List.unmodifiable(rows.map(DailyAnalyticsSummary.fromSupabase));
    }
  }

  Future<List<AnalyticsAlert>> loadAlerts({
    required DateTime start,
    required DateTime end,
  }) async {
    final alerts = <AnalyticsAlert>[];
    // An RPC exposes only published public alerts, including expired ones.
    // A missing RPC is an explicit error, not "0 alerts".
    for (var offset = 0; ; offset += 500) {
      final rows = await _client.rpc(
        'module5_alert_history',
        params: {
          'start_at': AnalyticsPeriod.utcBoundary(start).toIso8601String(),
          'end_at': AnalyticsPeriod.utcBoundary(end).toIso8601String(),
          'page_offset': offset,
        },
      );
      final page = rows as List;
      alerts.addAll(
        page.map(
          (row) => AnalyticsAlert.fromSupabase(
            Map<String, dynamic>.from(row as Map),
          ),
        ),
      );
      if (page.length < 500) break;
      if (offset >= 49500) {
        throw const FormatException(
          'Too many alert records. History was not loaded completely.',
        );
      }
    }
    return AnalyticsPeriod.deduplicate(alerts);
  }

  static String _dateOnly(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// Calendar calculations use Malaysia time, regardless of the device timezone.
/// Calendar dates are represented as UTC midnight; they are not instants.
class AnalyticsPeriod {
  static DateTime day(DateTime instant) {
    final malaysia = instant.toUtc().add(const Duration(hours: 8));
    return DateTime.utc(malaysia.year, malaysia.month, malaysia.day);
  }

  static DateTime monday(DateTime calendarDay) =>
      calendarDay.subtract(Duration(days: calendarDay.weekday - 1));

  static DateTime utcBoundary(DateTime calendarDay) =>
      calendarDay.subtract(const Duration(hours: 8));

  static List<AnalyticsAlert> deduplicate(Iterable<AnalyticsAlert> alerts) {
    final sorted = alerts.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final seen = <String>{};
    return List.unmodifiable(
      sorted.where(
        (alert) => seen.add(
          alert.dedupeKey?.trim().isNotEmpty == true
              ? 'key:${alert.dedupeKey!}'
              : 'id:${alert.id}',
        ),
      ),
    );
  }

  static List<AnalyticsAlert> alertsIn(
    Iterable<AnalyticsAlert> alerts,
    DateTime start,
    DateTime end, {
    String? routeId,
    bool dataHealth = false,
  }) => alerts.where((alert) {
    final date = day(alert.createdAt);
    return !date.isBefore(start) &&
        date.isBefore(end) &&
        alert.isDataHealth == dataHealth &&
        (routeId == null || alert.routeId == routeId);
  }).toList();

  static List<DailyAnalyticsSummary> summariesIn(
    Iterable<DailyAnalyticsSummary> summaries,
    DateTime start,
    DateTime end,
  ) => summaries
      .where(
        (summary) =>
            !summary.serviceDate.isBefore(start) &&
            summary.serviceDate.isBefore(end),
      )
      .toList();

  static int expectedChecks(DateTime start, DateTime end, DateTime now) {
    // Collector runs at :00 and :30. Allow two minutes for a running job.
    final cutoff = now.toUtc().subtract(const Duration(minutes: 2));
    final finish = utcBoundary(end);
    final until = cutoff.isBefore(finish) ? cutoff : finish;
    if (until.isBefore(utcBoundary(start))) return 0;
    final minutes = until.difference(utcBoundary(start)).inMinutes;
    return (minutes ~/ 30 + (until.isBefore(finish) ? 1 : 0)).clamp(
      0,
      end.difference(start).inDays * 48,
    );
  }
}

/// Spreadsheet-friendly report with explicit missing data and Malaysia dates.
/// Uses only already-loaded public records; never exports credentials/user data.
class WeeklyReportExport {
  static String date(DateTime day) =>
      '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

  static String csv({
    required DateTime start,
    required DateTime now,
    required String summary,
    required List<AnalyticsAlert> alerts,
    required List<DailyAnalyticsSummary> days,
  }) {
    final end = start.add(const Duration(days: 7));
    final today = AnalyticsPeriod.day(now);
    final included = AnalyticsPeriod.alertsIn(
      AnalyticsPeriod.deduplicate(
        alerts.where((a) => !a.createdAt.isAfter(now)),
      ),
      start,
      end,
    );
    final period =
        '${date(start)} / ${date(end.subtract(const Duration(days: 1)))}';
    final rows = <List<Object?>>[
      [
        'record_type',
        'date_or_period_MYT',
        'category',
        'route_id',
        'title',
        'message',
        'published_alerts',
        'saved_checks',
        'failed_checks',
        'known_congestion_percent',
        'delay_minutes',
        'scheduled_arrival_MYT',
        'estimated_arrival_MYT',
        'from_stop',
        'to_stop',
        'estimate_method',
        'observed_speed_kmh',
        'observation_duration_minutes',
        'status',
      ],
      [
        'summary',
        period,
        '',
        '',
        'NextRoute weekly bus service report',
        summary,
        included.length,
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        today.isBefore(end) ? 'Partial week' : 'Completed week',
      ],
      [
        'notes',
        period,
        '',
        '',
        'Scope and limitations',
        'Public archive records, not unique incidents or all operator disruptions. '
            'Blank values mean unavailable, not zero. Request success is not service reliability. '
            'Publisher values remain reported values; schedule_near_stop_position and gps_sustained_low_speed are labelled NextRoute estimates, not operator confirmations. '
            'Times use Malaysia UTC+08:00.',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ],
    ];
    for (var i = 0; i < 7; i++) {
      final day = start.add(Duration(days: i));
      final matches = days.where((d) => d.serviceDate == day);
      final sample = matches.isEmpty ? null : matches.first;
      final future = day.isAfter(today);
      rows.add([
        'daily',
        date(day),
        '',
        '',
        '',
        '',
        future
            ? ''
            : AnalyticsPeriod.alertsIn(
                included,
                day,
                day.add(const Duration(days: 1)),
              ).length,
        future ? '' : sample?.sampleCount,
        future ? '' : sample?.failedSampleCount,
        future ? '' : sample?.averageCongestionRate,
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
        future
            ? 'Not elapsed'
            : sample == null
            ? 'No collection records'
            : day == today
            ? 'Day in progress'
            : 'Recorded',
      ]);
    }
    for (final alert in included) {
      rows.add([
        'alert',
        '${alert.createdAt.toUtc().add(const Duration(hours: 8)).toIso8601String().replaceAll('Z', '')}+08:00',
        alert.type == TransitNotificationType.crowd
            ? 'congestion'
            : alert.type.name,
        alert.routeId,
        alert.title,
        alert.message,
        '',
        '',
        '',
        '',
        alert.delayMinutes,
        _instant(alert.scheduledArrival),
        _instant(alert.estimatedArrival),
        alert.fromStop,
        alert.toStop,
        alert.estimateMethod,
        alert.observedSpeedKmh,
        alert.observationDurationMinutes,
        'Published archive record',
      ]);
    }
    // Prevent spreadsheet formula execution from publisher-controlled text.
    Object? safe(Object? value) =>
        value is String && RegExp(r'^[\s\x00-\x1f]*[=+@-]').hasMatch(value)
        ? "'$value"
        : value ?? '';
    return '\uFEFF${const ListToCsvConverter().convert(rows.map((row) => row.map(safe).toList()).toList())}';
  }

  static String _instant(DateTime? instant) => instant == null
      ? ''
      : '${instant.toUtc().add(const Duration(hours: 8)).toIso8601String().replaceAll('Z', '')}+08:00';
}

class BusRouteInfo {
  const BusRouteInfo({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.sourceCategory,
  });

  final String id;
  final String shortName;
  final String longName;
  final String sourceCategory;

  String get displayName => shortName.isEmpty ? id : 'Route $shortName';
  String get routeCode => shortName.isEmpty ? id : shortName;
}

class BusRouteCatalog {
  const BusRouteCatalog._();

  static Future<Map<String, BusRouteInfo>> load() async {
    final routes = <String, BusRouteInfo>{};
    for (final source in const [
      (asset: 'assets/gtfs/bus/routes.txt', category: 'rapid-bus-kl'),
      (
        asset: 'assets/gtfs/mrt_feeder/routes.txt',
        category: 'rapid-bus-mrtfeeder',
      ),
    ]) {
      final asset = source.asset;
      final raw = await rootBundle.loadString(asset);
      final rows = const CsvToListConverter(eol: '\n').convert(raw);
      if (rows.isEmpty) continue;
      final headers = rows.first.map((value) => '$value'.trim()).toList();
      final idIndex = headers.indexOf('route_id');
      final shortNameIndex = headers.indexOf('route_short_name');
      final longNameIndex = headers.indexOf('route_long_name');
      if (idIndex < 0 || shortNameIndex < 0 || longNameIndex < 0) {
        throw FormatException('$asset is missing required route fields.');
      }
      for (final row in rows.skip(1)) {
        if (row.length <= longNameIndex) continue;
        final id = '${row[idIndex]}'.trim();
        if (id.isEmpty) continue;
        final shortName = '${row[shortNameIndex]}'.trim();
        final longName = '${row[longNameIndex]}'.trim();
        final routeCode = shortName.isNotEmpty
            ? shortName
            : longName.isNotEmpty
            ? longName
            : id;
        final description = shortName.isEmpty && longName == routeCode
            ? 'MRT feeder bus service'
            : longName;
        final info = BusRouteInfo(
          id: id,
          shortName: routeCode,
          longName: description,
          sourceCategory: source.category,
        );
        routes[id] = info;
        // MRT feeder realtime uses public codes (for example T559), whereas
        // routes.txt uses a numeric internal route_id and places that public
        // code in route_long_name. Keep both keys so live cards and alerts can
        // resolve the same route without rewriting teammate GTFS assets.
        final publicCode = routeCode;
        if (publicCode.isNotEmpty && publicCode != id) {
          routes.putIfAbsent(publicCode, () => info);
        }
      }
    }
    return Map.unmodifiable(routes);
  }

  static List<BusRouteInfo> selectable(Map<String, BusRouteInfo> routes) {
    final unique = <String, BusRouteInfo>{};
    for (final route in routes.values) {
      unique.putIfAbsent(route.routeCode.toUpperCase(), () => route);
    }
    final result = unique.values.toList()
      ..sort((a, b) => _naturalCode(a.routeCode, b.routeCode));
    return List.unmodifiable(result);
  }

  static bool matches(
    String? rawRouteId,
    String routeCode,
    Map<String, BusRouteInfo> routes,
  ) {
    if (rawRouteId == null) return false;
    final expected = routeCode.trim().toUpperCase();
    final actual =
        routes[rawRouteId]?.routeCode.toUpperCase() ??
        rawRouteId.trim().toUpperCase();
    return actual == expected;
  }

  static int _naturalCode(String first, String second) {
    final pattern = RegExp(r'^(\D*)(\d+)(.*)$');
    final a = pattern.firstMatch(first.toUpperCase());
    final b = pattern.firstMatch(second.toUpperCase());
    if (a == null || b == null) return first.compareTo(second);
    final prefix = a.group(1)!.compareTo(b.group(1)!);
    if (prefix != 0) return prefix;
    final number = int.parse(a.group(2)!).compareTo(int.parse(b.group(2)!));
    return number != 0 ? number : a.group(3)!.compareTo(b.group(3)!);
  }
}
