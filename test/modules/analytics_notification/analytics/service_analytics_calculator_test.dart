import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:nextroute_assignment/screens/service_analytics.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/services/analytics_service.dart';
import 'package:nextroute_assignment/services/module5_user_route_context.dart';

void main() {
  test('weekly CSV includes seven days, missing values and safe text', () {
    final csv = WeeklyReportExport.csv(
      start: DateTime.utc(2026, 8, 31),
      now: DateTime.utc(2026, 9, 5, 10),
      summary: 'Partial week',
      days: [],
      alerts: [
        AnalyticsAlert(
          id: 'safe',
          type: TransitNotificationType.delay,
          title: '=HYPERLINK("https://example.invalid")',
          message: '中文, commas\nand newlines',
          routeId: '@formula',
          createdAt: DateTime.utc(2026, 9, 5, 8),
          delayMinutes: 8,
          fromStop: 'Stop A',
          toStop: 'Terminal C',
          scheduledArrival: DateTime.utc(2026, 9, 5, 2, 30),
          estimatedArrival: DateTime.utc(2026, 9, 5, 2, 38),
          estimateMethod: 'schedule_stop_observation',
        ),
        AnalyticsAlert(
          id: 'future',
          type: TransitNotificationType.service,
          title: 'Future notice',
          message: 'Not yet published',
          createdAt: DateTime.utc(2026, 9, 6),
        ),
      ],
    );
    expect(csv.startsWith('\uFEFF'), isTrue);
    final rows = const CsvToListConverter().convert(csv.substring(1));
    expect(rows.every((row) => row.length == 19), isTrue);
    final daily = rows.where((row) => row[0] == 'daily').toList();
    expect(daily, hasLength(7));
    expect(daily.first[1], '2026-08-31');
    expect(daily.last[1], '2026-09-06');
    expect(daily.first[9], ''); // Missing congestion is not zero.
    expect(daily.last[6], ''); // Future alert count is not zero.
    expect(daily.last[18], 'Not elapsed');
    final alert = rows.singleWhere((row) => row[0] == 'alert');
    expect(alert[1], '2026-09-05T16:00:00.000+08:00');
    expect(alert[3], "'@formula");
    expect(alert[4], startsWith("'=HYPERLINK"));
    expect(alert[5], '中文, commas\nand newlines');
    expect(alert[10], 8);
    expect(alert[11], '2026-09-05T10:30:00.000+08:00');
    expect(alert[12], '2026-09-05T10:38:00.000+08:00');
    expect(alert[13], 'Stop A');
    expect(alert[14], 'Terminal C');
    expect(alert[15], 'schedule_stop_observation');
  });

  for (final outcome in ['saved', 'cancelled', 'failed']) {
    testWidgets('weekly download handles $outcome result', (tester) async {
      String? exported;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnalyticsHistoryView(
              report: true,
              summaries: const [],
              alerts: [_alert('a')],
              isLoading: false,
              error: null,
              alertsError: null,
              onRetry: () async {},
              now: DateTime.utc(2026, 9, 5, 10),
              saveReport: (name, bytes) async {
                expect(name, 'NextRoute-weekly-2026-08-31');
                exported = utf8.decode(bytes);
                if (outcome == 'failed') throw Exception('Disk unavailable');
                return outcome == 'cancelled' ? null : 'report.csv';
              },
            ),
          ),
        ),
      );
      final downloadButton = find.widgetWithText(
        FilledButton,
        'Download weekly CSV',
      );
      await tester.scrollUntilVisible(downloadButton, 250);
      // scrollUntilVisible stops when any part is visible; align the complete
      // button inside the viewport before sending the pointer event.
      await tester.ensureVisible(downloadButton);
      await tester.pumpAndSettle();
      await tester.tap(downloadButton);
      await tester.pumpAndSettle();
      expect(exported, contains('Delay a'));
      expect(
        find.textContaining(
          outcome == 'saved'
              ? 'Report saved:'
              : outcome == 'cancelled'
              ? 'Export cancelled'
              : 'Could not save report',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
  const calculator = ServiceAnalyticsCalculator();

  test('calculates vehicle and route counts with deterministic grouping', () {
    final feed = VehiclePositionFeed(
      totalEntities: 7,
      vehicles: [
        _vehicle(routeId: 'B'),
        _vehicle(routeId: 'A'),
        _vehicle(routeId: 'B'),
        _vehicle(routeId: 'C'),
        _vehicle(routeId: 'A'),
        _vehicle(routeId: null),
        _vehicle(routeId: ''),
      ],
    );

    final analytics = calculator.calculate(feed);

    expect(analytics.vehicleCount, 7);
    expect(analytics.routeCount, 3);
    expect(analytics.vehiclesByRoute, {'A': 2, 'B': 2, 'C': 1});
    expect(analytics.vehiclesByRoute.keys, orderedEquals(['A', 'B', 'C']));
  });

  test('selects the latest non-null vehicle timestamp', () {
    final first = DateTime.utc(2026, 8, 16, 8, 10);
    final latest = DateTime.utc(2026, 8, 16, 8, 15);
    final feed = VehiclePositionFeed(
      totalEntities: 3,
      vehicles: [
        _vehicle(timestamp: first),
        _vehicle(timestamp: null),
        _vehicle(timestamp: latest),
      ],
    );

    final analytics = calculator.calculate(feed);

    expect(analytics.latestUpdate, latest);
  });

  test('returns null latest update when all timestamps are missing', () {
    final feed = VehiclePositionFeed(
      totalEntities: 2,
      vehicles: [_vehicle(), _vehicle()],
    );

    final analytics = calculator.calculate(feed);

    expect(analytics.latestUpdate, isNull);
  });

  test('handles an empty feed', () {
    const feed = VehiclePositionFeed(totalEntities: 0, vehicles: []);

    final analytics = calculator.calculate(feed);

    expect(analytics.vehicleCount, 0);
    expect(analytics.routeCount, 0);
    expect(analytics.vehiclesByRoute, isEmpty);
    expect(analytics.latestUpdate, isNull);
  });

  test('counts reported congestion without treating stop-and-go as severe', () {
    final feed = VehiclePositionFeed(
      totalEntities: 5,
      vehicles: [
        _vehicle(congestionLevel: TransitCongestionLevel.smooth),
        _vehicle(congestionLevel: TransitCongestionLevel.stopAndGo),
        _vehicle(congestionLevel: TransitCongestionLevel.congested),
        _vehicle(congestionLevel: TransitCongestionLevel.severe),
        _vehicle(congestionLevel: TransitCongestionLevel.unknown),
      ],
    );

    final analytics = calculator.calculate(feed);

    expect(analytics.congestedVehicleCount, 2);
    expect(analytics.severeCongestionCount, 1);
    expect(analytics.congestionReportedVehicleCount, 4);
    expect(analytics.congestionRate, 50);
  });

  test('all unknown congestion is unavailable, not zero', () {
    final result = calculator.calculate(
      VehiclePositionFeed(totalEntities: 1, vehicles: [_vehicle()]),
    );
    expect(result.congestionRate, isNull);
    expect(result.congestionReportedVehicleCount, 0);
  });

  test('explicit smooth congestion can legitimately be zero', () {
    final result = calculator.calculate(
      VehiclePositionFeed(
        totalEntities: 1,
        vehicles: [_vehicle(congestionLevel: TransitCongestionLevel.smooth)],
      ),
    );
    expect(result.congestionRate, 0);
  });

  test('legacy SQL zero and SQL null never establish congestion coverage', () {
    for (final rate in [null, 0, 30]) {
      final day = DailyAnalyticsSummary.fromSupabase({
        'service_date': '2026-09-04',
        'average_congestion_rate': rate,
      });
      expect(day.averageCongestionRate, isNull);
      expect(day.serviceDate, DateTime.utc(2026, 9, 4));
    }
  });

  test('malformed congestion rates stay unknown even with coverage', () {
    for (final value in ['invalid', 'NaN', 'Infinity', -1, 101]) {
      final day = DailyAnalyticsSummary.fromSupabase({
        'service_date': '2026-09-04',
        'average_congestion_rate': value,
        'congestion_reported_observation_count': 10,
      });
      expect(day.averageCongestionRate, isNull);
    }
  });

  test('new summaries preserve real zero when known observations exist', () {
    final day = DailyAnalyticsSummary.fromSupabase({
      'service_date': '2026-09-04',
      'average_congestion_rate': 0,
      'congestion_reported_observation_count': 10,
    });
    expect(day.averageCongestionRate, 0);
  });

  test(
    'Malaysia midnight and Monday boundaries are independent of device time',
    () {
      expect(
        AnalyticsPeriod.day(DateTime.utc(2026, 9, 6, 15, 59)),
        DateTime.utc(2026, 9, 6),
      );
      final monday = AnalyticsPeriod.day(DateTime.utc(2026, 9, 6, 16));
      expect(monday, DateTime.utc(2026, 9, 7));
      expect(AnalyticsPeriod.monday(monday), monday);
      expect(
        AnalyticsPeriod.monday(DateTime.utc(2026, 9, 6)),
        DateTime.utc(2026, 8, 31),
      );
      expect(AnalyticsPeriod.utcBoundary(monday), DateTime.utc(2026, 9, 6, 16));
    },
  );

  test(
    'expected checks exclude future slots and allow two minutes to collect',
    () {
      final start = DateTime.utc(2026, 9, 7);
      final end = start.add(const Duration(days: 7));
      expect(
        AnalyticsPeriod.expectedChecks(
          start,
          end,
          DateTime.utc(2026, 9, 6, 16, 1, 59),
        ),
        0,
      );
      expect(
        AnalyticsPeriod.expectedChecks(
          start,
          end,
          DateTime.utc(2026, 9, 6, 16, 2),
        ),
        1,
      );
      expect(
        AnalyticsPeriod.expectedChecks(
          start,
          end,
          DateTime.utc(2026, 9, 6, 16, 32),
        ),
        2,
      );
      expect(
        AnalyticsPeriod.expectedChecks(start, end, DateTime.utc(2026, 9, 20)),
        336,
      );
    },
  );

  test(
    'duplicate keys count once; health notices are not travel disruptions',
    () {
      final start = DateTime.utc(2026, 9, 5);
      final alerts = AnalyticsPeriod.deduplicate([
        _alert('a', key: 'same'),
        _alert('b', key: 'same'),
        _alert('health', key: 'data-health:20260905'),
      ]);
      expect(alerts.length, 2);
      expect(
        AnalyticsPeriod.alertsIn(
          alerts,
          start,
          start.add(const Duration(days: 1)),
        ).length,
        1,
      );
      expect(
        AnalyticsPeriod.alertsIn(
          alerts,
          start,
          start.add(const Duration(days: 1)),
          dataHealth: true,
        ).length,
        1,
      );
    },
  );

  test('route filter and end-exclusive day window', () {
    final alerts = [_alert('a'), _alert('b', route: 'U2020')];
    final start = DateTime.utc(2026, 9, 5);
    expect(
      AnalyticsPeriod.alertsIn(
        alerts,
        start,
        start.add(const Duration(days: 1)),
        routeId: 'U6000',
      ).length,
      1,
    );
    expect(
      AnalyticsPeriod.alertsIn(
        alerts,
        start.subtract(const Duration(days: 1)),
        start,
      ),
      isEmpty,
    );
  });

  testWidgets('trend has daily axis, tooltip details and tap-to-filter', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_history(alerts: [_alert('a')]));
    expect(find.text('Explore service alerts'), findsOneWidget);
    expect(find.text('DAILY TRAVEL ALERTS'), findsOneWidget);
    expect(find.text('7\n5/9'), findsOneWidget);
    final tooltip = find.byWidgetPredicate(
      (w) => w is Tooltip && (w.message ?? '').startsWith('Sep 5, 2026'),
    );
    expect(tooltip, findsOneWidget);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(tooltip));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    expect(find.text(tester.widget<Tooltip>(tooltip).message!), findsOneWidget);
    await mouse.removePointer();
    await tester.tap(tooltip);
    await tester.pumpAndSettle();
    expect(find.text('ALERTS ON SEP 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly report is not the trend graph and marks partial week', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_history(report: true, alerts: [_alert('a')]));
    expect(find.text('Week in progress — not a final report'), findsOneWidget);
    expect(find.text('ALERTS BY CATEGORY'), findsOneWidget);
    expect(find.text('DAILY TRAVEL ALERTS'), findsNothing);
    expect(find.text('Aug 31 – Sep 6, 2026 • In progress'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history failure is not displayed as zero alerts', (
    tester,
  ) async {
    await tester.pumpWidget(_history(alertError: Exception('RPC missing')));
    expect(find.text('Cloud history needs attention'), findsOneWidget);
    expect(find.text('DAILY TRAVEL ALERTS'), findsNothing);
    expect(
      find.textContaining('No event totals or conclusions'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('route selection filters chart and alert list together', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _history(
        routeScope: 'U2020',
        alerts: [
          _alert('a'),
          _alert('b', route: 'U2020'),
        ],
      ),
    );
    expect(find.text('Delay a'), findsNothing);
    expect(find.text('Delay b'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty My Routes hides misleading zero analytics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _history(routeScope: '__my_routes__', alerts: [_alert('a')]),
    );
    expect(find.text('No routes selected'), findsOneWidget);
    expect(find.textContaining('using Manage'), findsOneWidget);
    expect(find.text('Trend metric'), findsNothing);
    expect(find.text('DAILY TRAVEL ALERTS'), findsNothing);
    expect(find.text('Delay a'), findsNothing);
    expect(find.text('Data source & quality details'), findsNothing);

    await tester.pumpWidget(
      _history(
        report: true,
        routeScope: '__my_routes__',
        alerts: [_alert('a')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No routes selected'), findsOneWidget);
    expect(find.text('Reporting week • Malaysia time'), findsNothing);
    expect(find.text('Delay alerts'), findsNothing);
    expect(find.text('Download weekly CSV'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active journey scope only shows its bus alerts', (tester) async {
    await tester.pumpWidget(
      _history(
        routeScope: module5ActiveJourneyScope,
        activeRoutes: const {'T250'},
        alerts: [
          _alert('active', route: 'T250'),
          _alert('other', route: '250'),
        ],
      ),
    );

    expect(find.textContaining('1 published travel alert(s)'), findsOneWidget);
    expect(find.textContaining('2 published travel alert(s)'), findsNothing);
  });

  testWidgets('previous week can be selected without showing current alerts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_history(report: true, alerts: [_alert('a')]));
    await tester.tap(find.text('Aug 31 – Sep 6, 2026 • In progress'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aug 24 – Aug 30, 2026').last);
    await tester.pumpAndSettle();
    expect(find.text('Week at a glance'), findsOneWidget);
    expect(find.text('Delay a'), findsNothing);
    expect(
      find.textContaining('No published travel alerts were found'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty data is explained honestly on a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_history());
    expect(
      find.textContaining('does not prove that no disruptions'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Data source & quality details'),
      300,
    );
    expect(find.text('Data source & quality details'), findsOneWidget);
    expect(find.textContaining('Congestion: N/A'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly mobile cards and controls do not overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_history(report: true, alerts: [_alert('a')]));
    await tester.scrollUntilVisible(find.text('Copy weekly report'), 250);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly report keeps estimated-delay evidence visible', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final estimate = AnalyticsAlert(
      id: 'estimate',
      type: TransitNotificationType.delay,
      title: 'Estimated delay on bus route U6000',
      message: 'Calculated from a fresh stopped-vehicle observation.',
      createdAt: DateTime.utc(2026, 9, 5, 8),
      routeId: 'U6000',
      delayMinutes: 8,
      vehicleLabel: 'vehicle-123',
      fromStop: 'Stop A',
      toStop: 'Terminal C',
      scheduledArrival: DateTime.utc(2026, 9, 5, 2, 30),
      estimatedArrival: DateTime.utc(2026, 9, 5, 2, 38),
      estimateMethod: 'schedule_stop_observation',
    );
    await tester.pumpWidget(_history(report: true, alerts: [estimate]));
    await tester.scrollUntilVisible(find.text(estimate.title), 300);
    await tester.tap(find.text(estimate.title));
    await tester.pumpAndSettle();
    expect(find.textContaining('Estimated delay: 8 min'), findsOneWidget);
    expect(find.textContaining('Scheduled arrival:'), findsOneWidget);
    expect(find.textContaining('Estimated arrival:'), findsOneWidget);
    expect(find.textContaining('Vehicle ID: vehicle-123'), findsOneWidget);
    expect(find.textContaining('not an operator Trip Update'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

AnalyticsAlert _alert(String id, {String? key, String route = 'U6000'}) =>
    AnalyticsAlert(
      id: id,
      type: TransitNotificationType.delay,
      title: 'Delay $id',
      message: 'Published test notice',
      createdAt: DateTime.utc(2026, 9, 5, 8),
      routeId: route,
      dedupeKey: key,
    );

Widget _history({
  bool report = false,
  List<AnalyticsAlert> alerts = const [],
  Object? alertError,
  String routeScope = '__all_network__',
  Set<String> activeRoutes = const {},
  Set<String> routineRoutes = const {},
}) => MaterialApp(
  home: Scaffold(
    body: AnalyticsHistoryView(
      report: report,
      summaries: const [],
      alerts: alerts,
      isLoading: false,
      error: null,
      alertsError: alertError,
      onRetry: () async {},
      now: DateTime.utc(2026, 9, 5, 10),
      routeScope: routeScope,
      activeRoutes: activeRoutes,
      routineRoutes: routineRoutes,
    ),
  ),
);

RealtimeVehicle _vehicle({
  String? routeId,
  DateTime? timestamp,
  TransitCongestionLevel congestionLevel = TransitCongestionLevel.unknown,
}) {
  return RealtimeVehicle(
    routeId: routeId,
    timestamp: timestamp,
    congestionLevel: congestionLevel,
  );
}
