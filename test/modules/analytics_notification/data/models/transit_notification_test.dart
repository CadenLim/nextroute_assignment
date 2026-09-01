import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';

void main() {
  test('parses a Supabase notification row', () {
    final notification = TransitNotification.fromSupabase({
      'id': 'notification-1',
      'notification_type': 'delay',
      'title': 'Delay notice',
      'message': 'Official delay information.',
      'route_id': 'U6000',
      'created_at': '2026-08-16T09:30:00Z',
      'origin': 'official',
      'severity': 'high',
    }, isRead: true);

    expect(notification.id, 'notification-1');
    expect(notification.type, TransitNotificationType.delay);
    expect(notification.routeId, 'U6000');
    expect(notification.createdAt, DateTime.utc(2026, 8, 16, 9, 30));
    expect(notification.isRead, isTrue);
    expect(notification.origin, TransitNotificationOrigin.official);
    expect(notification.severity, NotificationSeverity.high);
  });

  test('rejects unknown Supabase notification origins', () {
    expect(
      () => TransitNotification.fromSupabase({
        'id': 'notification-1',
        'notification_type': 'service',
        'title': 'Invalid notice',
        'message': 'Invalid origin.',
        'route_id': null,
        'created_at': '2026-08-16T09:30:00Z',
        'origin': 'demo',
        'severity': 'moderate',
      }, isRead: false),
      throwsFormatException,
    );
  });

  test('parses numeric Supabase analytics view values', () {
    final summary = DailyAnalyticsSummary.fromSupabase({
      'service_date': '2026-08-16',
      'sample_count': 48,
      'successful_sample_count': 47,
      'failed_sample_count': 1,
      'average_vehicle_count': '112.5',
      'average_route_count': 58.2,
      'average_congested_vehicle_count': '8.25',
      'average_severe_congestion_count': 2,
      'average_congestion_rate': '7.33',
      'feed_success_rate': 97.92,
      'peak_vehicle_count': 125,
      'peak_congested_vehicle_count': 13,
      'peak_severe_congestion_count': 4,
    });

    expect(summary.serviceDate, DateTime(2026, 8, 16));
    expect(summary.sampleCount, 48);
    expect(summary.averageVehicleCount, 112.5);
    expect(summary.averageCongestionRate, 7.33);
    expect(summary.feedSuccessRate, 97.92);
    expect(summary.peakSevereCongestionCount, 4);
  });
}
