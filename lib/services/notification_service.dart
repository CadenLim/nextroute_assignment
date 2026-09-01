import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

enum NotificationFilter { all, unread, congestion, push, delays }

typedef NotificationRowsLoader = Future<List<Map<String, dynamic>>> Function();

abstract interface class NotificationLocalStorage {
  Future<List<String>?> readNotificationRecords();

  Future<void> writeNotificationRecords(List<String> records);

  Future<String?> readNotificationPreferences();

  Future<void> writeNotificationPreferences(String preferencesJson);
}

class SharedPreferencesNotificationLocalStorage
    implements NotificationLocalStorage {
  SharedPreferencesNotificationLocalStorage({
    SharedPreferencesAsync? preferences,
  }) : _preferences = preferences ?? SharedPreferencesAsync();

  static const _notificationsKey = 'module5.transit_notifications';
  static const _preferencesKey = 'module5.notification_preferences';

  final SharedPreferencesAsync _preferences;

  @override
  Future<List<String>?> readNotificationRecords() {
    return _preferences.getStringList(_notificationsKey);
  }

  @override
  Future<void> writeNotificationRecords(List<String> records) {
    return _preferences.setStringList(_notificationsKey, records);
  }

  @override
  Future<String?> readNotificationPreferences() {
    return _preferences.getString(_preferencesKey);
  }

  @override
  Future<void> writeNotificationPreferences(String preferencesJson) {
    return _preferences.setString(_preferencesKey, preferencesJson);
  }
}

class LocalPushNotificationService {
  LocalPushNotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> requestPermission() async {
    if (!isSupported) {
      return false;
    }
    await _initialize();
    return await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission() ??
        false;
  }

  Future<void> show(TransitNotification notification) async {
    if (!isSupported) {
      return;
    }
    await _initialize();
    final urgent =
        notification.severity == NotificationSeverity.high ||
        notification.severity == NotificationSeverity.critical;
    await _plugin.show(
      id: notification.id.hashCode & 0x7fffffff,
      title: notification.title,
      body: notification.message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          'nextroute_alerts',
          'NextRoute alerts',
          channelDescription:
              'Congestion, delay, and public transport service alerts.',
          importance: urgent ? Importance.max : Importance.high,
          priority: urgent ? Priority.max : Priority.high,
        ),
      ),
      payload: notification.id,
    );
  }

  Future<void> _initialize() async {
    if (_initialized) {
      return;
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }
}

class NotificationRepository {
  NotificationRepository(
    this._storage, {
    this.supabaseClient,
    this.rowsLoader,
    this.pushService,
  });

  final NotificationLocalStorage _storage;
  final SupabaseClient? supabaseClient;
  final NotificationRowsLoader? rowsLoader;
  final LocalPushNotificationService? pushService;
  List<TransitNotification> _cachedNotifications = const [];

  SupabaseClient get _supabase => supabaseClient ?? Supabase.instance.client;

  Future<List<TransitNotification>> loadNotifications() async {
    final readIds = await _loadReadIds();
    final rows = rowsLoader == null
        ? await _loadSupabaseRows()
        : await rowsLoader!();
    final notifications = <TransitNotification>[];
    for (final row in rows) {
      try {
        final id = '${row['id']}';
        notifications.add(
          TransitNotification.fromSupabase(row, isRead: readIds.contains(id)),
        );
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    notifications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final preferences = await loadPreferences();
    _cachedNotifications = List.unmodifiable(
      notifications.where(
        (notification) => _notificationEnabled(notification, preferences),
      ),
    );
    return _cachedNotifications;
  }

  Future<List<TransitNotification>> markAsRead(String notificationId) async {
    final notifications = _cachedNotifications.isEmpty
        ? await loadNotifications()
        : _cachedNotifications;
    final updated = notifications
        .map(
          (notification) => notification.id == notificationId
              ? notification.copyWith(isRead: true)
              : notification,
        )
        .toList(growable: false);
    await _saveReadIds(updated);
    _cachedNotifications = List.unmodifiable(updated);
    return _cachedNotifications;
  }

  Future<List<TransitNotification>> markAllAsRead() async {
    final notifications = _cachedNotifications.isEmpty
        ? await loadNotifications()
        : _cachedNotifications;
    final updated = notifications
        .map((notification) => notification.copyWith(isRead: true))
        .toList(growable: false);
    await _saveReadIds(updated);
    _cachedNotifications = List.unmodifiable(updated);
    return _cachedNotifications;
  }

  RealtimeChannel subscribeToNotifications(VoidCallback onChanged) {
    return _supabase
        .channel('module5-notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          callback: (payload) async {
            try {
              final notification = TransitNotification.fromSupabase(
                payload.newRecord,
                isRead: false,
              );
              await showPushIfEnabled(notification);
            } on FormatException {
              // A malformed remote row is ignored and the list still reloads.
            }
            onChanged();
          },
        )
        .subscribe();
  }

  Future<void> removeSubscription(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }

  Future<List<Map<String, dynamic>>> _loadSupabaseRows() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final rows = await _supabase
        .from('notifications')
        .select()
        .eq('is_active', true)
        .or('expires_at.is.null,expires_at.gt.$now')
        .order('created_at', ascending: false)
        .limit(200);
    return rows
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Future<Set<String>> _loadReadIds() async {
    final records = await _storage.readNotificationRecords() ?? const [];
    final ids = <String>{};
    for (final record in records) {
      if (!record.trimLeft().startsWith('{')) {
        if (record.trim().isNotEmpty) ids.add(record.trim());
        continue;
      }
      try {
        final decoded = jsonDecode(record);
        if (decoded is Map<String, dynamic> && decoded['isRead'] == true) {
          final id = decoded['id'];
          if (id is String && id.isNotEmpty) ids.add(id);
        }
      } on FormatException {
        continue;
      }
    }
    return ids;
  }

  Future<void> _saveReadIds(Iterable<TransitNotification> notifications) {
    return _storage.writeNotificationRecords(
      notifications
          .where((notification) => notification.isRead)
          .map((notification) => notification.id)
          .toList(growable: false),
    );
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
      NotificationFilter.congestion => notifications.where(
        (notification) => notification.type == TransitNotificationType.crowd,
      ),
      NotificationFilter.push => notifications.where(
        (notification) => notification.type == TransitNotificationType.service,
      ),
      NotificationFilter.delays => notifications.where(
        (notification) => notification.type == TransitNotificationType.delay,
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

  Future<void> showPushIfEnabled(TransitNotification notification) async {
    final devicePush = pushService;
    if (devicePush == null) {
      return;
    }
    final preferences = await loadPreferences();
    if (!preferences.pushNotificationsEnabled ||
        !_notificationEnabled(notification, preferences)) {
      return;
    }
    try {
      await devicePush.show(notification);
    } on Object {
      // An alert remains in the in-app inbox if device notification fails.
    }
  }

  static bool _notificationEnabled(
    TransitNotification notification,
    NotificationPreferences preferences,
  ) {
    return switch (notification.type) {
      TransitNotificationType.service =>
        notification.origin == TransitNotificationOrigin.appGenerated
            ? preferences.realtimeDataAlertsEnabled
            : preferences.serviceAlertsEnabled,
      TransitNotificationType.delay => preferences.delayAlertsEnabled,
      TransitNotificationType.crowd => preferences.crowdAlertsEnabled,
    };
  }
}
