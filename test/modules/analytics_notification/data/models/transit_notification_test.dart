import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/transit_notification.dart';

void main() {
  test('TransitNotification completes a JSON round-trip', () {
    final createdAt = DateTime.utc(2026, 8, 16, 9, 30);
    final original = TransitNotification(
      id: 'notification-1',
      type: TransitNotificationType.delay,
      title: 'DEMO Delay Notice',
      message: 'DEMO content only.',
      routeId: 'DEMO-ROUTE',
      createdAt: createdAt,
      isRead: false,
      isDemo: true,
    );

    final decoded = TransitNotification.fromJson(original.toJson());

    expect(decoded.id, original.id);
    expect(decoded.type, original.type);
    expect(decoded.title, original.title);
    expect(decoded.message, original.message);
    expect(decoded.routeId, original.routeId);
    expect(decoded.createdAt, createdAt);
    expect(decoded.isRead, isFalse);
    expect(decoded.isDemo, isTrue);
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
        'isDemo': true,
      }),
      throwsFormatException,
    );
  });
}
