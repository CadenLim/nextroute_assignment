import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';

void main() {
  Map<String, dynamic> delayRow() => {
    'id': 'detail-test',
    'notification_type': 'delay',
    'title': 'Bus delay',
    'message': 'Publisher notice',
    'route_id': 'U6000',
    'created_at': '2026-09-05T08:00:00Z',
    'origin': 'official',
    'delay_minutes': 9,
    'vehicle_label': 'Bus 123',
    'from_stop': 'Stop A',
    'to_stop': 'Stop B',
    'direction': 'Towards B',
  };

  test('bus delay details survive read-state changes and can be searched', () {
    final notice = TransitNotification.fromSupabase(
      delayRow(),
      isRead: false,
    ).copyWith(isRead: true);
    expect(notice.delayLabel, 'Reported delay: 9 min');
    expect(notice.vehicleLabel, 'Bus 123');
    expect(notice.fromStop, 'Stop A');
    expect(notice.toStop, 'Stop B');
    expect(notice.direction, 'Towards B');
    expect(notice.matchesSearch('u6000 123'), isTrue);
    expect(notice.matchesSearch(' stop b '), isTrue);
    expect(
      notice.matchesSearch('Unknown City', routeName: 'Unknown City loop'),
      isTrue,
    );
    expect(notice.matchesSearch('u6000 missing'), isFalse);
    expect(notice.matchesSearch('   '), isTrue);
  });

  test('missing or malformed delay values remain unknown, not zero', () {
    for (final value in [null, -1, 1441, 1.5, '9', double.nan]) {
      final notice = TransitNotification.fromSupabase({
        ...delayRow(),
        'delay_minutes': value,
      }, isRead: false);
      expect(notice.delayMinutes, isNull);
      expect(notice.delayLabel, 'Delay duration not provided');
      expect(notice.message, 'Publisher notice');
    }
    final zero = TransitNotification.fromSupabase({
      ...delayRow(),
      'delay_minutes': 0,
    }, isRead: false);
    expect(zero.delayLabel, 'Reported delay: 0 min');
  });

  test('old notification schema remains supported without bus details', () {
    final row = delayRow()
      ..remove('delay_minutes')
      ..remove('vehicle_label')
      ..remove('from_stop')
      ..remove('to_stop')
      ..remove('direction');
    final notice = TransitNotification.fromSupabase(row, isRead: false);
    expect(notice.delayMinutes, isNull);
    expect(notice.fromStop, isNull);
    expect(notice.direction, isNull);
  });

  test('parses auditable NextRoute delay estimate fields', () {
    final row = <String, dynamic>{
      ...delayRow(),
      'origin': 'appGenerated',
      'dedupe_key': 'estimated-delay:test',
      'trip_id': 'U6000_U600001_0',
      'observed_stop_id': 'stop-a',
      'scheduled_arrival': '2026-09-05T02:30:00Z',
      'estimated_arrival': '2026-09-05T02:39:00Z',
      'estimate_method': 'schedule_near_stop_position',
    };
    final notice = TransitNotification.fromSupabase(row, isRead: false);
    expect(notice.isEstimatedDelay, isTrue);
    expect(notice.delayLabel, 'Estimated delay: 9 min');
    expect(notice.tripId, 'U6000_U600001_0');
    expect(notice.observedStopId, 'stop-a');
    expect(notice.scheduledArrival, DateTime.utc(2026, 9, 5, 2, 30));
    expect(notice.estimatedArrival, DateTime.utc(2026, 9, 5, 2, 39));
    expect(notice.matchesSearch('U600001 stop-a'), isTrue);

    final archived = AnalyticsAlert.fromSupabase(row);
    expect(archived.isEstimatedDelay, isTrue);
    expect(archived.delayMinutes, 9);
    expect(archived.fromStop, 'Stop A');
    expect(archived.toStop, 'Stop B');
    expect(archived.scheduledArrival, DateTime.utc(2026, 9, 5, 2, 30));
  });

  test('parses labelled GPS congestion estimate fields', () {
    final row = <String, dynamic>{
      ...delayRow(),
      'notification_type': 'crowd',
      'title': 'Possible congestion',
      'message': 'Two consecutive low-speed observations.',
      'estimate_method': 'gps_low_speed_two_intervals',
      'observed_speed_kmh': 4.25,
      'observation_duration_minutes': 10,
    };
    final notice = TransitNotification.fromSupabase(row, isRead: false);
    expect(notice.isEstimatedCongestion, isTrue);
    expect(notice.observedSpeedKmh, 4.25);
    expect(notice.observationDurationMinutes, 10);

    final archived = AnalyticsAlert.fromSupabase(row);
    expect(archived.isEstimatedCongestion, isTrue);
    expect(archived.observedSpeedKmh, 4.25);
  });

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
      'congestion_reported_observation_count': 100,
      'feed_success_rate': 97.92,
      'peak_vehicle_count': 125,
      'peak_congested_vehicle_count': 13,
      'peak_severe_congestion_count': 4,
    });

    expect(summary.serviceDate, DateTime.utc(2026, 8, 16));
    expect(summary.sampleCount, 48);
    expect(summary.averageVehicleCount, 112.5);
    expect(summary.averageCongestionRate, 7.33);
    expect(summary.feedSuccessRate, 97.92);
    expect(summary.peakSevereCongestionCount, 4);
  });
}
