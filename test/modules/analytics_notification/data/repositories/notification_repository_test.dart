import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/services/notification_service.dart';

void main() {
  test(
    'loads real Supabase rows without creating demo notifications',
    () async {
      final storage = _FakeNotificationLocalStorage();
      final repository = NotificationRepository(
        storage,
        rowsLoader: () async => [
          _row(id: 'older', createdAt: '2026-08-16T09:00:00Z'),
          _row(
            id: 'newer',
            createdAt: '2026-08-16T10:00:00Z',
            type: 'crowd',
            routeId: 'U6000',
            origin: 'appGenerated',
          ),
        ],
      );

      final notifications = await repository.loadNotifications();

      expect(notifications.map((item) => item.id), ['newer', 'older']);
      expect(notifications.first.routeId, 'U6000');
      expect(
        notifications.first.origin,
        TransitNotificationOrigin.appGenerated,
      );
      expect(storage.notificationWriteCount, 0);
    },
  );

  test(
    'an empty remote inbox stays empty and does not seed demo data',
    () async {
      final storage = _FakeNotificationLocalStorage();
      final repository = NotificationRepository(
        storage,
        rowsLoader: () async => const [],
      );

      expect(await repository.loadNotifications(), isEmpty);
      expect(storage.notificationWriteCount, 0);
    },
  );

  test('skips malformed Supabase rows without crashing', () async {
    final repository = NotificationRepository(
      _FakeNotificationLocalStorage(),
      rowsLoader: () async => [
        _row(id: 'valid'),
        _row(id: 'bad-date', createdAt: 'not-a-date'),
        _row(id: 'bad-origin', origin: 'demo'),
      ],
    );

    final notifications = await repository.loadNotifications();

    expect(notifications, hasLength(1));
    expect(notifications.single.id, 'valid');
  });

  test('marking notifications read persists only their remote IDs', () async {
    final storage = _FakeNotificationLocalStorage();
    Future<List<Map<String, dynamic>>> rows() async => [
      _row(id: 'first', createdAt: '2026-08-16T10:00:00Z'),
      _row(id: 'second', createdAt: '2026-08-16T09:00:00Z'),
    ];
    final repository = NotificationRepository(storage, rowsLoader: rows);
    await repository.loadNotifications();

    final updated = await repository.markAsRead('first');
    final reloaded = await NotificationRepository(
      storage,
      rowsLoader: rows,
    ).loadNotifications();

    expect(updated.first.isRead, isTrue);
    expect(updated.last.isRead, isFalse);
    expect(storage.notificationRecords, ['first']);
    expect(reloaded.first.isRead, isTrue);
    expect(reloaded.last.isRead, isFalse);
  });

  test(
    'legacy read JSON is migrated without loading its old content',
    () async {
      final storage = _FakeNotificationLocalStorage(
        notificationRecords: [
          jsonEncode({
            'id': 'remote-1',
            'isRead': true,
            'title': 'Old local row',
          }),
        ],
      );
      final repository = NotificationRepository(
        storage,
        rowsLoader: () async => [_row(id: 'remote-1')],
      );

      final notifications = await repository.loadNotifications();

      expect(notifications.single.id, 'remote-1');
      expect(notifications.single.isRead, isTrue);
      expect(notifications.single.title, 'Service notice');
    },
  );

  test('calculates unread count and filters notification categories', () {
    final repository = NotificationRepository(
      _FakeNotificationLocalStorage(),
      rowsLoader: () async => const [],
    );
    final notifications = [
      _notification(id: 'congestion', type: TransitNotificationType.crowd),
      _notification(
        id: 'service',
        type: TransitNotificationType.service,
        isRead: true,
      ),
      _notification(id: 'delay', type: TransitNotificationType.delay),
    ];

    expect(repository.unreadCount(notifications), 2);
    expect(
      repository
          .filterNotifications(notifications, NotificationFilter.unread)
          .map((item) => item.id),
      ['congestion', 'delay'],
    );
    expect(
      repository
          .filterNotifications(notifications, NotificationFilter.congestion)
          .single
          .id,
      'congestion',
    );
    expect(
      repository
          .filterNotifications(notifications, NotificationFilter.push)
          .single
          .id,
      'service',
    );
    expect(
      repository
          .filterNotifications(notifications, NotificationFilter.delays)
          .single
          .id,
      'delay',
    );
  });

  test('notification preferences default, persist, and filter rows', () async {
    final storage = _FakeNotificationLocalStorage();
    final repository = NotificationRepository(
      storage,
      rowsLoader: () async => [
        _row(id: 'official-service'),
        _row(id: 'data-health', origin: 'appGenerated'),
        _row(id: 'congestion', type: 'crowd', origin: 'appGenerated'),
      ],
    );

    final defaults = await repository.loadPreferences();
    expect(defaults.serviceAlertsEnabled, isTrue);
    expect(defaults.realtimeDataAlertsEnabled, isTrue);
    expect(defaults.pushNotificationsEnabled, isFalse);

    await repository.savePreferences(
      const NotificationPreferences(
        serviceAlertsEnabled: false,
        delayAlertsEnabled: true,
        crowdAlertsEnabled: true,
        realtimeDataAlertsEnabled: false,
        pushNotificationsEnabled: false,
      ),
    );

    final notifications = await repository.loadNotifications();
    expect(notifications.map((item) => item.id), ['congestion']);
  });

  test('old preference JSON keeps new switches at safe defaults', () async {
    final storage = _FakeNotificationLocalStorage(
      preferencesJson: jsonEncode({
        'serviceAlertsEnabled': false,
        'delayAlertsEnabled': false,
        'crowdAlertsEnabled': false,
      }),
    );
    final repository = NotificationRepository(
      storage,
      rowsLoader: () async => const [],
    );

    final preferences = await repository.loadPreferences();

    expect(preferences.realtimeDataAlertsEnabled, isTrue);
    expect(preferences.pushNotificationsEnabled, isFalse);
  });
}

Map<String, dynamic> _row({
  required String id,
  String type = 'service',
  String createdAt = '2026-08-16T09:30:00Z',
  String origin = 'official',
  String? routeId,
}) {
  return {
    'id': id,
    'notification_type': type,
    'title': 'Service notice',
    'message': 'Real Supabase notification content.',
    'route_id': routeId,
    'created_at': createdAt,
    'origin': origin,
    'severity': 'moderate',
  };
}

TransitNotification _notification({
  required String id,
  required TransitNotificationType type,
  bool isRead = false,
}) {
  return TransitNotification(
    id: id,
    type: type,
    title: 'Service notice',
    message: 'Real notification content.',
    routeId: null,
    createdAt: DateTime.utc(2026, 8, 16, 9),
    isRead: isRead,
    origin: TransitNotificationOrigin.official,
  );
}

class _FakeNotificationLocalStorage implements NotificationLocalStorage {
  _FakeNotificationLocalStorage({
    this.notificationRecords,
    this.preferencesJson,
  });

  List<String>? notificationRecords;
  String? preferencesJson;
  int notificationWriteCount = 0;

  @override
  Future<List<String>?> readNotificationRecords() async =>
      notificationRecords == null
      ? null
      : List<String>.from(notificationRecords!);

  @override
  Future<void> writeNotificationRecords(List<String> records) async {
    notificationRecords = List<String>.from(records);
    notificationWriteCount += 1;
  }

  @override
  Future<String?> readNotificationPreferences() async => preferencesJson;

  @override
  Future<void> writeNotificationPreferences(String preferencesJson) async {
    this.preferencesJson = preferencesJson;
  }
}
