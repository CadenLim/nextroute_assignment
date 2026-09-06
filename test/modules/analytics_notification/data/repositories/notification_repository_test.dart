import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:nextroute_assignment/screens/notification_centre.dart';
import 'package:nextroute_assignment/models/analytics_notification_models.dart';
import 'package:nextroute_assignment/services/notification_service.dart';
import 'package:nextroute_assignment/services/module5_route_preferences.dart';

void main() {
  testWidgets('notification controls scroll in keyboard-sized embedded space', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = NotificationRepository(
      _FakeNotificationLocalStorage(),
      rowsLoader: () async => [_expiredRow()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 250,
              child: NotificationCentreScreen(
                repository: repository,
                embedded: true,
                enableRealtime: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Expired • History'),
      150,
      scrollable: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.pumpAndSettle();
    final historyRect = tester.getRect(find.text('Expired • History'));
    expect(historyRect.top, greaterThanOrEqualTo(0));
    expect(historyRect.bottom, lessThanOrEqualTo(250));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('bus delay details and search work on a narrow screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = NotificationRepository(
      _FakeNotificationLocalStorage(),
      rowsLoader: () async => [
        {
          ..._row(id: 'delay', type: 'delay', routeId: 'U6000'),
          'title': 'Bus delay test',
          'delay_minutes': 9,
          'vehicle_label': 'Bus 123',
          'from_stop': 'Stop A',
          'to_stop': 'Stop B',
          'direction': 'Towards B',
          'scheduled_arrival': '2026-09-05T02:30:00Z',
          'estimated_arrival': '2026-09-05T02:39:00Z',
          'estimate_method': 'schedule_stop_observation',
        },
      ],
    );
    final routes = Module5RoutePreferences();
    addTearDown(routes.dispose);
    await routes.replace(['U6000']);
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCentreScreen(
          repository: repository,
          enableRealtime: false,
          routePreferences: routes,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Estimated delay: 9 min'), findsOneWidget);
    expect(find.textContaining('Scheduled arrival:'), findsOneWidget);
    expect(find.textContaining('Estimated arrival:'), findsOneWidget);
    expect(find.text('Observed at: Stop A'), findsOneWidget);
    expect(find.text('Towards: Stop B'), findsOneWidget);
    expect(find.text('Direction: Towards B'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '123 stop b');
    await tester.pumpAndSettle();
    expect(find.text('Bus delay test'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'not-a-matching-route');
    await tester.pumpAndSettle();
    expect(find.textContaining('No matching notifications'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Bus delay test'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  test(
    'expired messages remain in history, never in current or unread',
    () async {
      final repository = NotificationRepository(
        _FakeNotificationLocalStorage(),
        rowsLoader: () async => [_row(id: 'current'), _expiredRow()],
      );
      final notifications = await repository.loadNotifications();
      expect(notifications, hasLength(2));
      expect(repository.unreadCount(notifications), 1);
      expect(
        repository
            .filterNotifications(notifications, NotificationFilter.all)
            .single
            .id,
        'current',
      );
      expect(
        repository
            .filterNotifications(notifications, NotificationFilter.unread)
            .single
            .id,
        'current',
      );
      final history = repository.filterNotifications(
        notifications,
        NotificationFilter.history,
      );
      expect(history.single.id, 'expired');
      expect(history.single.message, 'Real Supabase notification content.');
      expect(
        repository.filterNotifications([
          history.single,
        ], NotificationFilter.service),
        isEmpty,
      );
      expect(
        history.single.copyWith(isRead: true).expiresAt,
        history.single.expiresAt,
      );
    },
  );

  test(
    'expiration boundary is inclusive and withdrawn rows are hidden',
    () async {
      final row = _expiredRow();
      final notification = TransitNotification.fromSupabase(row, isRead: false);
      expect(notification.isExpiredAt(notification.expiresAt!), isTrue);
      expect(notification.isCurrentAt(notification.expiresAt!), isFalse);
      final repository = NotificationRepository(
        _FakeNotificationLocalStorage(),
        rowsLoader: () async => [
          row,
          {..._row(id: 'withdrawn'), 'is_active': false},
        ],
      );
      expect((await repository.loadNotifications()).map((n) => n.id), [
        'expired',
      ]);
    },
  );

  test(
    'history remains readable when its current-alert preference is disabled',
    () async {
      final repository = NotificationRepository(
        _FakeNotificationLocalStorage(
          preferencesJson: jsonEncode(
            const NotificationPreferences.defaults()
                .copyWith(serviceAlertsEnabled: false)
                .toJson(),
          ),
        ),
        rowsLoader: () async => [_row(id: 'muted-current'), _expiredRow()],
      );
      final notifications = await repository.loadNotifications();
      expect(notifications.single.id, 'expired');
      expect(repository.unreadCount(notifications), 0);
    },
  );

  test(
    'mark all read affects current notices and preserves older saved IDs',
    () async {
      final storage = _FakeNotificationLocalStorage(
        notificationRecords: ['older-page-read-id'],
      );
      final repository = NotificationRepository(
        storage,
        rowsLoader: () async => [_row(id: 'current'), _expiredRow()],
      );
      await repository.loadNotifications();
      final updated = await repository.markAllAsRead();
      expect(updated.singleWhere((n) => n.id == 'current').isRead, isTrue);
      expect(updated.singleWhere((n) => n.id == 'expired').isRead, isFalse);
      expect(
        storage.notificationRecords,
        containsAll(['older-page-read-id', 'current']),
      );
    },
  );

  test('expired or withdrawn notifications cannot trigger push', () async {
    final push = _RecordingPush();
    final repository = NotificationRepository(
      _FakeNotificationLocalStorage(
        preferencesJson: jsonEncode(
          const NotificationPreferences.defaults()
              .copyWith(pushNotificationsEnabled: true)
              .toJson(),
        ),
      ),
      pushService: push,
    );
    await repository.showPushIfEnabled(
      TransitNotification.fromSupabase(_expiredRow(), isRead: false),
    );
    await repository.showPushIfEnabled(
      TransitNotification.fromSupabase({
        ..._row(id: 'withdrawn'),
        'is_active': false,
      }, isRead: false),
    );
    expect(push.shown, 0);
    await repository.showPushIfEnabled(
      TransitNotification.fromSupabase(_row(id: 'current'), isRead: false),
    );
    expect(push.shown, 1);
  });

  testWidgets('History displays expired message and date on mobile', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = NotificationRepository(
      _FakeNotificationLocalStorage(),
      rowsLoader: () async => [_expiredRow()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCentreScreen(
          repository: repository,
          enableRealtime: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose My Routes'), findsWidgets);
    expect(find.text('0 unread (current)'), findsOneWidget);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(find.text('Real Supabase notification content.'), findsOneWidget);
    expect(find.text('Expired • History'), findsOneWidget);
    expect(find.textContaining('Expired:'), findsOneWidget);
    expect(
      find.text('Unread'),
      findsOneWidget,
    ); // Filter chip only, not a card badge.
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('refresh remains available for an empty inbox', (tester) async {
    var loads = 0;
    final repository = NotificationRepository(
      _FakeNotificationLocalStorage(),
      rowsLoader: () async {
        loads++;
        return [];
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationCentreScreen(
          repository: repository,
          enableRealtime: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Refresh notifications'));
    await tester.pumpAndSettle();
    expect(loads, 2);
    await tester.pumpWidget(const SizedBox.shrink());
  });
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
          .filterNotifications(notifications, NotificationFilter.service)
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

Map<String, dynamic> _expiredRow() => {
  ..._row(
    id: 'expired',
    createdAt: DateTime.now()
        .toUtc()
        .subtract(const Duration(days: 2))
        .toIso8601String(),
  ),
  'expires_at': DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 1))
      .toIso8601String(),
  'is_active': true,
};

class _RecordingPush extends LocalPushNotificationService {
  int shown = 0;
  @override
  Future<void> show(TransitNotification notification) async {
    shown++;
  }
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
