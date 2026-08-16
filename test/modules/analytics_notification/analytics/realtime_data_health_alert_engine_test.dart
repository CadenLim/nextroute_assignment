import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/analytics/realtime_data_health_alert_engine.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/service_analytics.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/transit_notification.dart';

void main() {
  final now = DateTime.utc(2026, 8, 16, 10);

  group('stale realtime data rule', () {
    test('does not alert for a 30-second-old update', () {
      final engine = RealtimeDataHealthAlertEngine(now: () => now);

      final alert = engine.recordSuccessfulFetch(
        _analytics(latestUpdate: now.subtract(const Duration(seconds: 30))),
      );

      expect(alert, isNull);
    });

    test('does not alert at the exact two-minute boundary', () {
      final engine = RealtimeDataHealthAlertEngine(now: () => now);

      final alert = engine.recordSuccessfulFetch(
        _analytics(latestUpdate: now.subtract(realtimeDataStaleThreshold)),
      );

      expect(alert, isNull);
    });

    test('alerts when the update is more than two minutes old', () {
      final engine = RealtimeDataHealthAlertEngine(now: () => now);

      final alert = engine.recordSuccessfulFetch(
        _analytics(
          latestUpdate: now.subtract(
            realtimeDataStaleThreshold + const Duration(seconds: 1),
          ),
        ),
      );

      expect(alert, isNotNull);
      expect(alert!.id, staleRealtimeDataNotificationId);
      expect(alert.origin, TransitNotificationOrigin.appGenerated);
      expect(alert.createdAt, now);
    });

    test('does not invent a stale alert when latest update is null', () {
      final engine = RealtimeDataHealthAlertEngine(now: () => now);

      final alert = engine.recordSuccessfulFetch(
        _analytics(latestUpdate: null),
      );

      expect(alert, isNull);
    });
  });

  group('consecutive fetch failure rule', () {
    test('alerts on the third consecutive failure', () {
      final engine = RealtimeDataHealthAlertEngine(now: () => now);

      expect(engine.recordFailedFetch(), isNull);
      expect(engine.recordFailedFetch(), isNull);
      final alert = engine.recordFailedFetch();

      expect(alert, isNotNull);
      expect(alert!.id, unavailableRealtimeDataNotificationId);
      expect(alert.origin, TransitNotificationOrigin.appGenerated);
      expect(engine.consecutiveFailureCount, 3);
    });

    test('a successful fetch resets the failure count', () {
      final engine = RealtimeDataHealthAlertEngine(now: () => now);

      expect(engine.recordFailedFetch(), isNull);
      expect(engine.recordFailedFetch(), isNull);
      expect(
        engine.recordSuccessfulFetch(_analytics(latestUpdate: null)),
        isNull,
      );
      expect(engine.consecutiveFailureCount, 0);
      expect(engine.recordFailedFetch(), isNull);
      expect(engine.recordFailedFetch(), isNull);
      expect(engine.recordFailedFetch(), isNotNull);
    });
  });
}

ServiceAnalytics _analytics({required DateTime? latestUpdate}) {
  return ServiceAnalytics(
    vehicleCount: 0,
    routeCount: 0,
    vehiclesByRoute: const {},
    latestUpdate: latestUpdate,
  );
}
