import 'dart:convert';

import 'package:nextroute_assignment/modules/analytics_notification/data/models/notification_preferences.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/models/transit_notification.dart';
import 'package:nextroute_assignment/modules/analytics_notification/data/storage/notification_local_storage.dart';

enum NotificationFilter { all, unread }

class NotificationRepository {
  NotificationRepository(this._storage, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final NotificationLocalStorage _storage;
  final DateTime Function() _now;

  Future<List<TransitNotification>> loadNotifications() async {
    final storedRecords = await _storage.readNotificationRecords();
    if (storedRecords == null) {
      final demoNotifications = _createDemoNotifications(_now().toUtc());
      await saveNotifications(demoNotifications);
      return List.unmodifiable(demoNotifications);
    }

    final notifications = <TransitNotification>[];
    for (final record in storedRecords) {
      try {
        final decoded = jsonDecode(record);
        if (decoded is Map<String, dynamic>) {
          notifications.add(TransitNotification.fromJson(decoded));
        }
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    return List.unmodifiable(notifications);
  }

  Future<void> saveNotifications(Iterable<TransitNotification> notifications) {
    final records = notifications
        .map((notification) => jsonEncode(notification.toJson()))
        .toList(growable: false);
    return _storage.writeNotificationRecords(records);
  }

  Future<List<TransitNotification>> markAsRead(String notificationId) async {
    final notifications = await loadNotifications();
    final updated = notifications
        .map(
          (notification) => notification.id == notificationId
              ? notification.copyWith(isRead: true)
              : notification,
        )
        .toList(growable: false);
    await saveNotifications(updated);
    return List.unmodifiable(updated);
  }

  Future<List<TransitNotification>> markAllAsRead() async {
    final notifications = await loadNotifications();
    final updated = notifications
        .map((notification) => notification.copyWith(isRead: true))
        .toList(growable: false);
    await saveNotifications(updated);
    return List.unmodifiable(updated);
  }

  int unreadCount(Iterable<TransitNotification> notifications) {
    return notifications.where((notification) => !notification.isRead).length;
  }

  List<TransitNotification> filterNotifications(
    Iterable<TransitNotification> notifications,
    NotificationFilter filter,
  ) {
    return List.unmodifiable(switch (filter) {
      NotificationFilter.all => notifications,
      NotificationFilter.unread => notifications.where(
        (notification) => !notification.isRead,
      ),
    });
  }

  Future<NotificationPreferences> loadPreferences() async {
    final storedJson = await _storage.readNotificationPreferences();
    if (storedJson == null) {
      return const NotificationPreferences.defaults();
    }

    try {
      final decoded = jsonDecode(storedJson);
      if (decoded is Map<String, dynamic>) {
        return NotificationPreferences.fromJson(decoded);
      }
    } on FormatException {
      return const NotificationPreferences.defaults();
    } on TypeError {
      return const NotificationPreferences.defaults();
    }
    return const NotificationPreferences.defaults();
  }

  Future<void> savePreferences(NotificationPreferences preferences) {
    return _storage.writeNotificationPreferences(
      jsonEncode(preferences.toJson()),
    );
  }

  static List<TransitNotification> _createDemoNotifications(DateTime now) {
    return [
      TransitNotification(
        id: 'demo-service-notice',
        type: TransitNotificationType.service,
        title: 'DEMO Service Notice',
        message:
            'DEMO only: Example service information for testing this local '
            'inbox. This is not a live transport alert.',
        routeId: null,
        createdAt: now.subtract(const Duration(minutes: 5)),
        isRead: false,
        isDemo: true,
      ),
      TransitNotification(
        id: 'demo-delay-notice',
        type: TransitNotificationType.delay,
        title: 'DEMO Delay Notice',
        message:
            'DEMO only: Example delay content for testing read status. No '
            'delay was calculated from the live feed.',
        routeId: 'DEMO-ROUTE',
        createdAt: now.subtract(const Duration(minutes: 30)),
        isRead: false,
        isDemo: true,
      ),
      TransitNotification(
        id: 'demo-crowd-notice',
        type: TransitNotificationType.crowd,
        title: 'DEMO Crowd Notice',
        message:
            'DEMO only: Example crowd content for local UI testing. It is '
            'not based on official or live crowd data.',
        routeId: null,
        createdAt: now.subtract(const Duration(hours: 1)),
        isRead: false,
        isDemo: true,
      ),
    ];
  }
}
