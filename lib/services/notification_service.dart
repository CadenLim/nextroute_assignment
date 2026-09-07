import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'api_service.dart';
import 'personal_assistance_functions.dart';
import 'personal_travel_service.dart';

enum NotificationFilter {
  all,
  unread,
  congestion,
  service,
  delays,
  dataStatus,
  history,
}

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
  static const int _legacyDailyCommuteNotificationBaseId = 7800;
  static const MethodChannel _deviceChannel = MethodChannel('nextroute/device');

  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<bool> requestPermission() async {
    if (!isSupported) {
      return false;
    }
    await _initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final notificationsAllowed =
        await android?.requestNotificationsPermission() ?? true;
    final exactAlarmsAllowed =
        await android?.requestExactAlarmsPermission() ?? true;
    return notificationsAllowed && exactAlarmsAllowed;
  }

  Future<void> show(TransitNotification notification) async {
    if (!isSupported || !notification.isCurrentAt(DateTime.now().toUtc())) {
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

  Future<void> cancelDailyCommuteNotifications(DailyCommute commute) async {
    if (!isSupported) return;
    await _initialize();
    for (var weekday = DateTime.monday; weekday <= DateTime.sunday; weekday++) {
      await _plugin.cancel(id: notificationId(commute, weekday));
      await _plugin.cancel(id: _legacyDailyCommuteNotificationBaseId + weekday);
    }
  }

  Future<void> scheduleDailyCommuteNotifications(DailyCommute commute) async {
    if (!isSupported || !commute.reminderEnabled) return;
    await _initialize();
    final notificationTime = commute.notificationTimeMinutes;
    final leaveTime = _formatMinutes(commute.recommendedDepartureMinutes);
    final arriveTime = _formatMinutes(commute.arriveByMinutes);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_commute_reminders',
        'Daily commute reminders',
        channelDescription:
            'Weekly reminders for the configured NextRoute daily commute.',
        importance: Importance.high,
        priority: Priority.high,
      ),
    );

    for (final arrivalWeekday in commute.activeDays) {
      final notificationWeekday = commute.notificationWeekdayForArrivalDay(
        arrivalWeekday,
      );
      await _plugin.zonedSchedule(
        id: notificationId(commute, arrivalWeekday),
        title: 'NextRoute – Time to leave soon',
        body:
            'Your trip to ${commute.destination} takes about '
            '${commute.estimatedDurationMinutes} minutes. Leave by $leaveTime '
            'to arrive by $arriveTime.',
        scheduledDate: _nextWeekdayTime(notificationWeekday, notificationTime),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: 'daily_commute:${commute.id}:$arrivalWeekday',
      );
    }
  }

  int notificationId(DailyCommute commute, int arrivalWeekday) {
    final identity =
        commute.id ??
        '${commute.userId}|${commute.savedRouteId}|${commute.arriveByMinutes}';
    var hash = 0x811c9dc5;
    for (final unit in identity.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x0fffffff;
    }
    return hash * 8 + arrivalWeekday;
  }

  tz.TZDateTime _nextWeekdayTime(int weekday, int minutes) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      minutes ~/ 60,
      minutes % 60,
    );
    while (scheduled.weekday != weekday || !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static String _formatMinutes(int minutes) {
    final normalized = (minutes % 1440 + 1440) % 1440;
    final hour24 = normalized ~/ 60;
    final minute = normalized % 60;
    final period = hour24 >= 12 ? 'PM' : 'AM';
    final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
    return '$hour12:${minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _initialize() async {
    if (_initialized) {
      return;
    }
    tz_data.initializeTimeZones();
    final deviceTimezone =
        await _deviceChannel.invokeMethod<String>('getLocalTimezone') ?? 'UTC';
    final timezoneName = switch (deviceTimezone) {
      // The compact timezone database omits this equivalent alias.
      'Asia/Kuala_Lumpur' => 'Asia/Singapore',
      'GMT' || 'UTC' => 'Etc/UTC',
      final identifier => identifier,
    };
    tz.setLocalLocation(tz.getLocation(timezoneName));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _initialized = true;
  }
}

class NotificationRepository {
  static const historyLimit = 200;
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
        (notification) =>
            notification.isActive &&
            !notification.createdAt.isAfter(DateTime.now().toUtc()) &&
            (notification.isExpiredAt(DateTime.now().toUtc()) ||
                _notificationEnabled(notification, preferences)),
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
        .map(
          (notification) => notification.isCurrentAt(DateTime.now().toUtc())
              ? notification.copyWith(isRead: true)
              : notification,
        )
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
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'notifications',
          callback: (_) => onChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'notifications',
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  Future<void> removeSubscription(RealtimeChannel channel) async {
    await _supabase.removeChannel(channel);
  }

  Future<List<Map<String, dynamic>>> _loadSupabaseRows() async {
    final now = DateTime.now().toUtc().toIso8601String();
    // Separate limits keep a busy archive from displacing current alerts.
    final pages = await Future.wait([
      _supabase
          .from('notifications')
          .select()
          .eq('is_active', true)
          .lte('created_at', now)
          .or('expires_at.is.null,expires_at.gt.$now')
          .order('created_at', ascending: false)
          .order('id')
          .limit(200),
      _supabase
          .from('notifications')
          .select()
          .eq('is_active', true)
          .lte('created_at', now)
          .lte('expires_at', now)
          .order('created_at', ascending: false)
          .order('id')
          .limit(historyLimit),
    ]);
    return pages
        .expand((rows) => rows)
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

  Future<void> _saveReadIds(Iterable<TransitNotification> notifications) async {
    final ids = await _loadReadIds();
    ids.addAll(notifications.where((n) => n.isRead).map((n) => n.id));
    return _storage.writeNotificationRecords(ids.toList(growable: false));
  }

  int unreadCount(Iterable<TransitNotification> notifications) {
    final now = DateTime.now().toUtc();
    return notifications
        .where(
          (notification) =>
              !notification.isRead && notification.isCurrentAt(now),
        )
        .length;
  }

  List<TransitNotification> filterNotifications(
    Iterable<TransitNotification> notifications,
    NotificationFilter filter,
  ) {
    final now = DateTime.now().toUtc();
    if (filter == NotificationFilter.history) {
      return List.unmodifiable(
        notifications.where(
          (notification) =>
              notification.isActive &&
              notification.isExpiredAt(now) &&
              !notification.createdAt.isAfter(now),
        ),
      );
    }
    notifications = notifications.where(
      (notification) => notification.isCurrentAt(now),
    );
    return List.unmodifiable(switch (filter) {
      NotificationFilter.all => notifications,
      NotificationFilter.unread => notifications.where(
        (notification) => !notification.isRead,
      ),
      NotificationFilter.congestion => notifications.where(
        (notification) => notification.type == TransitNotificationType.crowd,
      ),
      NotificationFilter.service => notifications.where(
        (notification) =>
            notification.type == TransitNotificationType.service &&
            !notification.isDataHealth,
      ),
      NotificationFilter.delays => notifications.where(
        (notification) => notification.type == TransitNotificationType.delay,
      ),
      NotificationFilter.dataStatus => notifications.where(
        (notification) => notification.isDataHealth,
      ),
      NotificationFilter.history => const <TransitNotification>[],
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
    if (!notification.isCurrentAt(DateTime.now().toUtc())) return;
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

// -----------------------------------------------------------------------------
// Daily Commute model
// -----------------------------------------------------------------------------

class DailyCommute {
  const DailyCommute({
    this.id,
    required this.userId,
    required this.savedRouteId,
    required this.origin,
    required this.destination,
    required this.arriveByMinutes,
    required this.activeDays,
    required this.reminderEnabled,
    required this.reminderMinutesBefore,
    required this.estimatedDurationMinutes,
    this.updatedAt,
  });

  factory DailyCommute.fromJson(Map<String, dynamic> json) {
    final timeParts = json['arrive_by'].toString().split(':');
    final hour = int.tryParse(timeParts.first) ?? 9;
    final minute = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
    return DailyCommute(
      id: json['id'] as String?,
      userId: json['user_id'] as String,
      savedRouteId: json['saved_route_id'] as String?,
      origin: json['origin'] as String,
      destination: json['destination'] as String,
      arriveByMinutes: hour * 60 + minute,
      activeDays: Set<int>.from(json['active_days'] as List),
      reminderEnabled: json['reminder_enabled'] as bool? ?? true,
      reminderMinutesBefore:
          (json['reminder_minutes_before'] as num?)?.toInt() ?? 10,
      estimatedDurationMinutes:
          (json['estimated_duration_minutes'] as num?)?.toInt() ?? 1,
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  final String? id;
  final String userId;
  final String? savedRouteId;
  final String origin;
  final String destination;
  final int arriveByMinutes;
  final Set<int> activeDays;
  final bool reminderEnabled;
  final int reminderMinutesBefore;
  final int estimatedDurationMinutes;
  final DateTime? updatedAt;

  int get recommendedDepartureMinutes =>
      _minutesInDay(arriveByMinutes - estimatedDurationMinutes);

  int get notificationTimeMinutes =>
      _minutesInDay(recommendedDepartureMinutes - reminderMinutesBefore);

  int notificationWeekdayForArrivalDay(int arrivalWeekday) {
    final rawNotificationMinutes =
        arriveByMinutes - estimatedDurationMinutes - reminderMinutesBefore;
    final dayOffset = rawNotificationMinutes < 0 ? -1 : 0;
    return (arrivalWeekday - 1 + dayOffset) % 7 + 1;
  }

  DateTime? nextReminderAfter(DateTime now) {
    if (!reminderEnabled || activeDays.isEmpty) return null;
    DateTime? next;
    for (var offset = 0; offset <= 7; offset++) {
      final arrivalDay = DateTime(now.year, now.month, now.day + offset);
      if (!activeDays.contains(arrivalDay.weekday)) continue;
      final arrival = DateTime(
        arrivalDay.year,
        arrivalDay.month,
        arrivalDay.day,
        arriveByMinutes ~/ 60,
        arriveByMinutes % 60,
      );
      final reminder = arrival.subtract(
        Duration(minutes: estimatedDurationMinutes + reminderMinutesBefore),
      );
      if (!reminder.isAfter(now)) continue;
      if (next == null || reminder.isBefore(next)) next = reminder;
    }
    return next;
  }

  DailyCommute copyWith({
    String? id,
    String? userId,
    String? savedRouteId,
    String? origin,
    String? destination,
    int? arriveByMinutes,
    Set<int>? activeDays,
    bool? reminderEnabled,
    int? reminderMinutesBefore,
    int? estimatedDurationMinutes,
    DateTime? updatedAt,
  }) {
    return DailyCommute(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      savedRouteId: savedRouteId ?? this.savedRouteId,
      origin: origin ?? this.origin,
      destination: destination ?? this.destination,
      arriveByMinutes: arriveByMinutes ?? this.arriveByMinutes,
      activeDays: activeDays ?? this.activeDays,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderMinutesBefore:
          reminderMinutesBefore ?? this.reminderMinutesBefore,
      estimatedDurationMinutes:
          estimatedDurationMinutes ?? this.estimatedDurationMinutes,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toUpsert() => {
    if (id != null) 'id': id,
    'user_id': userId,
    'saved_route_id': savedRouteId,
    'origin': origin,
    'destination': destination,
    'arrive_by': _databaseTime(arriveByMinutes),
    'active_days': activeDays.toList()..sort(),
    'reminder_enabled': reminderEnabled,
    'reminder_minutes_before': reminderMinutesBefore,
    'estimated_duration_minutes': estimatedDurationMinutes,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  static int _minutesInDay(int value) => (value % 1440 + 1440) % 1440;

  static String _databaseTime(int minutes) {
    final normalized = _minutesInDay(minutes);
    return '${(normalized ~/ 60).toString().padLeft(2, '0')}:'
        '${(normalized % 60).toString().padLeft(2, '0')}:00';
  }
}

// -----------------------------------------------------------------------------
// Daily Commute persistence and scheduling
// -----------------------------------------------------------------------------

abstract interface class DailyCommuteRepository {
  Future<List<DailyCommute>> loadAll();
  Future<DailyCommute> upsert(DailyCommute commute);
  Future<void> delete(String id);
}

class SupabaseDailyCommuteRepository implements DailyCommuteRepository {
  SupabaseDailyCommuteRepository({SupabaseClient? client})
    : _functions = PersonalAssistanceFunctions(client: client);

  final PersonalAssistanceFunctions _functions;

  @override
  Future<List<DailyCommute>> loadAll() async {
    final rows = await _functions.list('daily-commutes', 'list');
    return rows.map(DailyCommute.fromJson).toList();
  }

  @override
  Future<DailyCommute> upsert(DailyCommute commute) async {
    final commuteData = commute.toUpsert()..remove('user_id');
    try {
      final response = await _functions.invoke(
        'daily-commutes',
        'upsert',
        payload: {'commute': commuteData},
      );
      final row = Map<String, dynamic>.from(response['data'] as Map);
      return DailyCommute.fromJson(row);
    } on FunctionsHttpException catch (error) {
      if (error.status != 409) rethrow;
      dynamic details = error.details;
      if (details is String) {
        try {
          details = jsonDecode(details);
        } catch (_) {}
      }
      final message = details is Map ? details['error']?.toString() : null;
      throw StateError(
        message == null || message.isEmpty
            ? 'An identical Daily Commute already exists.'
            : message,
      );
    }
  }

  @override
  Future<void> delete(String id) async {
    await _functions.invoke('daily-commutes', 'delete', payload: {'id': id});
  }
}

class NotificationPermissionException implements Exception {
  const NotificationPermissionException();

  @override
  String toString() =>
      'Notification permission is required to enable reminders.';
}

class UpcomingDailyCommuteReminder {
  const UpcomingDailyCommuteReminder({
    required this.commute,
    required this.time,
  });

  final DailyCommute commute;
  final DateTime time;
}

class DailyCommuteService {
  DailyCommuteService({
    DailyCommuteRepository? repository,
    ApiService? apiService,
    LocalPushNotificationService? notificationService,
    SupabaseClient? client,
    this.userIdProvider,
  }) : repository =
           repository ?? SupabaseDailyCommuteRepository(client: client),
       _apiService = apiService ?? ApiService(),
       _notificationService =
           notificationService ?? LocalPushNotificationService(),
       _client = client;

  final DailyCommuteRepository repository;
  final ApiService _apiService;
  final LocalPushNotificationService _notificationService;
  final SupabaseClient? _client;
  final String Function()? userIdProvider;

  Future<List<DailyCommute>> loadAll() => repository.loadAll();

  static UpcomingDailyCommuteReminder? nextReminder(
    Iterable<DailyCommute> commutes,
    DateTime now,
  ) {
    UpcomingDailyCommuteReminder? nearest;
    for (final commute in commutes) {
      final time = commute.nextReminderAfter(now);
      if (time == null) continue;
      if (nearest == null || time.isBefore(nearest.time)) {
        nearest = UpcomingDailyCommuteReminder(commute: commute, time: time);
      }
    }
    return nearest;
  }

  Future<int> estimateDuration(SavedRoute route) async {
    final stations = await _apiService.loadAllStations();
    final origin = route.resolveOrigin(stations);
    final destination = route.resolveDestination(stations);
    if (origin == null || destination == null) {
      throw StateError(
        'This favourite route contains a station that is no longer available.',
      );
    }

    final routes = await _apiService.findRoutes(origin, destination);
    if (routes.isEmpty) {
      throw StateError('No route is currently available for this commute.');
    }
    final preferred = routes.cast<Map<String, dynamic>?>().firstWhere(
      (result) => result != null && route.matchesJourney(result),
      orElse: () => null,
    );
    final selected = preferred ?? routes.first;
    final match = RegExp(r'\d+').firstMatch(selected['duration'].toString());
    final minutes = int.tryParse(match?.group(0) ?? '');
    if (minutes == null || minutes <= 0) {
      throw StateError('Unable to calculate the journey duration.');
    }
    return minutes;
  }

  Future<DailyCommute> save({
    String? reminderId,
    SavedRoute? route,
    String? origin,
    String? destination,
    int? estimatedDurationMinutes,
    required int arriveByMinutes,
    required Set<int> activeDays,
    required bool reminderEnabled,
    required int reminderMinutesBefore,
  }) async {
    final routeId = route?.id;
    final commuteOrigin = route?.origin.name ?? origin?.trim();
    final commuteDestination = route?.destination.name ?? destination?.trim();
    final duration = route == null
        ? estimatedDurationMinutes
        : await estimateDuration(route);
    if (commuteOrigin == null ||
        commuteOrigin.isEmpty ||
        commuteDestination == null ||
        commuteDestination.isEmpty) {
      throw ArgumentError('Choose an origin and destination.');
    }
    if (duration == null || duration <= 0) {
      throw ArgumentError('Choose a valid travel duration.');
    }
    if (activeDays.isEmpty) {
      throw ArgumentError('Select at least one active day.');
    }
    if (arriveByMinutes < 0 || arriveByMinutes >= 1440) {
      throw ArgumentError('Choose a valid arrival time.');
    }
    if (!const {5, 10, 15, 30}.contains(reminderMinutesBefore)) {
      throw ArgumentError('Choose a valid reminder time.');
    }
    await _ensureUniqueSettings(
      reminderId: reminderId,
      savedRouteId: routeId,
      origin: commuteOrigin,
      destination: commuteDestination,
      arriveByMinutes: arriveByMinutes,
      activeDays: activeDays,
      reminderEnabled: reminderEnabled,
      reminderMinutesBefore: reminderMinutesBefore,
    );
    if (reminderEnabled && _notificationService.isSupported) {
      final allowed = await _notificationService.requestPermission();
      if (!allowed) throw const NotificationPermissionException();
    }

    final userId =
        userIdProvider?.call() ??
        (_client ?? Supabase.instance.client).auth.currentUser?.id;
    if (userId == null) throw const AuthException('Please sign in again.');
    final saved = await repository.upsert(
      DailyCommute(
        id: reminderId,
        userId: userId,
        savedRouteId: routeId,
        origin: commuteOrigin,
        destination: commuteDestination,
        arriveByMinutes: arriveByMinutes,
        activeDays: activeDays,
        reminderEnabled: reminderEnabled,
        reminderMinutesBefore: reminderMinutesBefore,
        estimatedDurationMinutes: duration,
      ),
    );

    await _notificationService.cancelDailyCommuteNotifications(saved);
    if (saved.reminderEnabled) {
      await _notificationService.scheduleDailyCommuteNotifications(saved);
    }
    return saved;
  }

  Future<DailyCommute> setReminderEnabled(
    DailyCommute commute,
    bool enabled,
  ) async {
    await _ensureUniqueSettings(
      reminderId: commute.id,
      savedRouteId: commute.savedRouteId,
      origin: commute.origin,
      destination: commute.destination,
      arriveByMinutes: commute.arriveByMinutes,
      activeDays: commute.activeDays,
      reminderEnabled: enabled,
      reminderMinutesBefore: commute.reminderMinutesBefore,
    );
    if (enabled && _notificationService.isSupported) {
      final allowed = await _notificationService.requestPermission();
      if (!allowed) throw const NotificationPermissionException();
    }
    final saved = await repository.upsert(
      commute.copyWith(reminderEnabled: enabled),
    );
    await _notificationService.cancelDailyCommuteNotifications(saved);
    if (enabled) {
      await _notificationService.scheduleDailyCommuteNotifications(saved);
    }
    return saved;
  }

  Future<void> delete(DailyCommute commute) async {
    final id = commute.id;
    if (id == null) throw ArgumentError('This reminder does not have an ID.');
    await repository.delete(id);
    await _notificationService.cancelDailyCommuteNotifications(commute);
  }

  Future<void> _ensureUniqueSettings({
    required String? reminderId,
    required String? savedRouteId,
    required String origin,
    required String destination,
    required int arriveByMinutes,
    required Set<int> activeDays,
    required bool reminderEnabled,
    required int reminderMinutesBefore,
  }) async {
    final commutes = await repository.loadAll();
    final duplicate = commutes.any(
      (commute) =>
          commute.id != reminderId &&
          commute.savedRouteId == savedRouteId &&
          commute.origin.trim().toLowerCase() == origin.trim().toLowerCase() &&
          commute.destination.trim().toLowerCase() ==
              destination.trim().toLowerCase() &&
          commute.arriveByMinutes == arriveByMinutes &&
          commute.activeDays.length == activeDays.length &&
          commute.activeDays.containsAll(activeDays) &&
          commute.reminderEnabled == reminderEnabled &&
          commute.reminderMinutesBefore == reminderMinutesBefore,
    );
    if (duplicate) {
      throw StateError('An identical Daily Commute already exists.');
    }
  }
}
