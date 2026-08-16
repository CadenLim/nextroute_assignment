import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/transit_notification.dart';

void main() {
  test('legacy Phase 3 demo JSON loads with demo origin', () {
    final decoded = TransitNotification.fromJson({
      'id': 'legacy-demo',
      'type': 'service',
      'title': 'DEMO Service Notice',
      'message': 'DEMO content only.',
      'routeId': null,
      'createdAt': '2026-08-16T09:30:00.000Z',
      'isRead': false,
      'isDemo': true,
    });

    expect(decoded.origin, TransitNotificationOrigin.demo);
    expect(decoded.isDemo, isTrue);
  });

  test('new notification origin completes a JSON round-trip', () {
    final createdAt = DateTime.utc(2026, 8, 16, 9, 30);
    final original = TransitNotification(
      id: 'notification-1',
      type: TransitNotificationType.delay,
      title: 'DEMO Delay Notice',
      message: 'DEMO content only.',
      routeId: 'DEMO-ROUTE',
      createdAt: createdAt,
      isRead: false,
      origin: TransitNotificationOrigin.appGenerated,
    );

    final decoded = TransitNotification.fromJson(original.toJson());

    expect(decoded.id, original.id);
    expect(decoded.type, original.type);
    expect(decoded.title, original.title);
    expect(decoded.message, original.message);
    expect(decoded.routeId, original.routeId);
    expect(decoded.createdAt, createdAt);
    expect(decoded.isRead, isFalse);
    expect(decoded.origin, TransitNotificationOrigin.appGenerated);
    expect(decoded.isDemo, isFalse);
    expect(original.toJson()['origin'], 'appGenerated');
    expect(original.toJson().containsKey('isDemo'), isFalse);
  });

  test('TransitNotification rejects an invalid origin', () {
    expect(
      () => TransitNotification.fromJson({
        'id': 'notification-1',
        'type': 'service',
        'title': 'Data warning',
        'message': 'App-generated content.',
        'routeId': null,
        'createdAt': '2026-08-16T09:30:00.000Z',
        'isRead': false,
        'origin': 'unknown-origin',
      }),
      throwsFormatException,
    );
  });

  test('legacy non-demo JSON is not assumed to be official', () {
    expect(
      () => TransitNotification.fromJson({
        'id': 'legacy-unknown',
        'type': 'service',
        'title': 'Legacy notice',
        'message': 'Legacy content.',
        'routeId': null,
        'createdAt': '2026-08-16T09:30:00.000Z',
        'isRead': false,
        'isDemo': false,
      }),
      throwsFormatException,
    );
  });

  test('TransitNotification rejects an invalid timestamp', () {
    expect(
      () => TransitNotification.fromJson({
        'id': 'notification-1',
        'type': 'service',
        'title': 'DEMO Service Notice',
        'message': 'DEMO content only.',
        'routeId': null,
        'createdAt': 'not-a-timestamp',
        'isRead': false,
        'origin': 'demo',
      }),
      throwsFormatException,
    );
  });
}
