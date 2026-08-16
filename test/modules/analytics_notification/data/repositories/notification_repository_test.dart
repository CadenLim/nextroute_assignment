import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/notification_preferences.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/transit_notification.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/repositories/notification_repository.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/storage/notification_local_storage.dart';

void main() {
  final fixedNow = DateTime.utc(2026, 8, 16, 10);

  test('seeds clearly labelled demo records on first use only', () async {
    final storage = _FakeNotificationLocalStorage();
    final repository = NotificationRepository(storage, now: () => fixedNow);

    final firstLoad = await repository.loadNotifications();
    final writesAfterFirstLoad = storage.notificationWriteCount;
    final secondLoad = await repository.loadNotifications();

    expect(firstLoad, hasLength(3));
    expect(firstLoad.every((notification) => notification.isDemo), isTrue);
    expect(
      firstLoad.every((notification) => notification.title.contains('DEMO')),
      isTrue,
    );
    expect(writesAfterFirstLoad, 1);
    expect(storage.notificationWriteCount, 1);
    expect(
      secondLoad.map((notification) => notification.id),
      firstLoad.map((notification) => notification.id),
    );
  });

  test('calculates unread count and filters unread notifications', () {
    final repository = NotificationRepository(_FakeNotificationLocalStorage());
    final notifications = [
      _notification(id: 'read', isRead: true),
      _notification(id: 'unread-1'),
      _notification(id: 'unread-2'),
    ];

    expect(repository.unreadCount(notifications), 2);
    expect(
      repository
          .filterNotifications(notifications, NotificationFilter.unread)
          .map((notification) => notification.id),
      ['unread-1', 'unread-2'],
    );
    expect(
      repository.filterNotifications(notifications, NotificationFilter.all),
      hasLength(3),
    );
  });

  test('marking one notification read is persisted', () async {
    final storage = _FakeNotificationLocalStorage();
    final repository = NotificationRepository(storage);
    await repository.saveNotifications([
      _notification(id: 'first'),
      _notification(id: 'second'),
    ]);

    final updated = await repository.markAsRead('first');
    final reloaded = await NotificationRepository(storage).loadNotifications();

    expect(updated.first.isRead, isTrue);
    expect(updated.last.isRead, isFalse);
    expect(reloaded.first.isRead, isTrue);
    expect(reloaded.last.isRead, isFalse);
  });

  test('marking all notifications read is persisted', () async {
    final storage = _FakeNotificationLocalStorage();
    final repository = NotificationRepository(storage);
    await repository.saveNotifications([
      _notification(id: 'first'),
      _notification(id: 'second'),
    ]);

    final updated = await repository.markAllAsRead();
    final reloaded = await NotificationRepository(storage).loadNotifications();

    expect(updated.every((notification) => notification.isRead), isTrue);
    expect(reloaded.every((notification) => notification.isRead), isTrue);
  });

  test(
    'skips malformed stored records without reseeding or crashing',
    () async {
      final valid = _notification(id: 'valid');
      final storage = _FakeNotificationLocalStorage(
        notificationRecords: [
          jsonEncode(valid.toJson()),
          '{not valid json',
          jsonEncode({
            ...valid.toJson(),
            'id': 'invalid-date',
            'createdAt': 'not-a-date',
          }),
        ],
      );
      final repository = NotificationRepository(storage, now: () => fixedNow);

      final loaded = await repository.loadNotifications();

      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'valid');
      expect(storage.notificationWriteCount, 0);
    },
  );

  test(
    'notification preferences default and persist through storage',
    () async {
      final storage = _FakeNotificationLocalStorage();
      final repository = NotificationRepository(storage);

      final defaults = await repository.loadPreferences();
      expect(defaults.serviceAlertsEnabled, isTrue);
      expect(defaults.delayAlertsEnabled, isTrue);
      expect(defaults.crowdAlertsEnabled, isTrue);

      const updated = NotificationPreferences(
        serviceAlertsEnabled: false,
        delayAlertsEnabled: true,
        crowdAlertsEnabled: false,
      );
      await repository.savePreferences(updated);
      final reloaded = await NotificationRepository(storage).loadPreferences();

      expect(reloaded.serviceAlertsEnabled, isFalse);
      expect(reloaded.delayAlertsEnabled, isTrue);
      expect(reloaded.crowdAlertsEnabled, isFalse);
    },
  );
}

TransitNotification _notification({required String id, bool isRead = false}) {
  return TransitNotification(
    id: id,
    type: TransitNotificationType.service,
    title: 'DEMO Service Notice',
    message: 'DEMO content only.',
    routeId: null,
    createdAt: DateTime.utc(2026, 8, 16, 9),
    isRead: isRead,
    isDemo: true,
  );
}

class _FakeNotificationLocalStorage implements NotificationLocalStorage {
  _FakeNotificationLocalStorage({this.notificationRecords});

  List<String>? notificationRecords;
  String? preferencesJson;
  int notificationWriteCount = 0;

  @override
  Future<List<String>?> readNotificationRecords() async {
    return notificationRecords == null
        ? null
        : List<String>.from(notificationRecords!);
  }

  @override
  Future<void> writeNotificationRecords(List<String> records) async {
    notificationRecords = List<String>.from(records);
    notificationWriteCount += 1;
  }

  @override
  Future<String?> readNotificationPreferences() async {
    return preferencesJson;
  }

  @override
  Future<void> writeNotificationPreferences(String preferencesJson) async {
    this.preferencesJson = preferencesJson;
  }
}
