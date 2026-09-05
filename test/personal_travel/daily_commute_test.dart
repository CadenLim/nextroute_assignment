import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/screens/personal_travel.dart';
import 'package:nextroute_assignment/services/api_service.dart';
import 'package:nextroute_assignment/services/notification_service.dart';
import 'package:nextroute_assignment/services/personal_travel_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class MemoryCommuteRepository implements DailyCommuteRepository {
  DailyCommute? value;
  int saves = 0;

  @override
  Future<DailyCommute?> load() async => value;

  @override
  Future<DailyCommute> upsert(DailyCommute commute) async {
    saves++;
    value = commute;
    return commute;
  }

  @override
  Future<void> delete() async => value = null;
}

class MemorySavedRoutes implements SavedRoutesRepository {
  MemorySavedRoutes(this.route);

  final SavedRoute route;

  @override
  Future<int> count() async => 1;

  @override
  Future<void> delete(String id) async {}

  @override
  Future<List<SavedRoute>> load() async => [route];

  @override
  Future<void> rename(String id, String name) async {}

  @override
  Future<void> save(SavedRoute route) async {}
}

class CommuteApi extends ApiService {
  CommuteApi(this.route, {this.duration = '35 min'});

  final SavedRoute route;
  final String duration;

  @override
  Future<List<StationModel>> loadAllStations() async => [
    route.origin,
    route.destination,
  ];

  @override
  Future<List<Map<String, dynamic>>> findRoutes(
    StationModel origin,
    StationModel destination,
  ) async => [
    {'sig': route.signature, 'duration': duration},
  ];
}

class CommuteNotifications extends LocalPushNotificationService {
  CommuteNotifications({this.permission = true});

  final bool permission;
  int cancellations = 0;
  DailyCommute? scheduled;

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> cancelDailyCommuteNotifications() async => cancellations++;

  @override
  Future<void> scheduleDailyCommuteNotifications(DailyCommute commute) async {
    scheduled = commute;
  }
}

SavedRoute commuteRoute() => SavedRoute(
  id: 'route-1',
  name: 'Campus commute',
  origin: StationModel(
    ids: ['origin'],
    name: 'Home',
    lines: {'KJ'},
    category: 'Rail',
    lat: 3.0,
    lon: 101.0,
  ),
  destination: StationModel(
    ids: ['destination'],
    name: 'TAR UMT',
    lines: {'KJ'},
    category: 'Rail',
    lat: 3.1,
    lon: 101.1,
  ),
  signature: 'DIR_KJ',
  lineName: 'Kelana Jaya',
);

void main() {
  test('notification timezone exists in the bundled timezone database', () {
    tz_data.initializeTimeZones();
    expect(() => tz.getLocation('Asia/Singapore'), returnsNormally);
  });

  test('calculates departure and notification time from arrival time', () {
    final commute = DailyCommute(
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'TAR UMT',
      arriveByMinutes: 9 * 60,
      activeDays: const {1, 2, 3, 4, 5},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
    );

    expect(commute.recommendedDepartureMinutes, 8 * 60 + 25);
    expect(commute.notificationTimeMinutes, 8 * 60 + 15);
  });

  test('moves an after-midnight commute reminder to the previous weekday', () {
    final commute = DailyCommute(
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'TAR UMT',
      arriveByMinutes: 20,
      activeDays: const {DateTime.monday},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
    );

    expect(commute.notificationTimeMinutes, 23 * 60 + 35);
    expect(
      commute.notificationWeekdayForArrivalDay(DateTime.monday),
      DateTime.sunday,
    );
  });

  test(
    'save reuses route API duration and replaces scheduled notifications',
    () async {
      final route = commuteRoute();
      final repository = MemoryCommuteRepository();
      final notifications = CommuteNotifications();
      final service = DailyCommuteService(
        repository: repository,
        apiService: CommuteApi(route),
        notificationService: notifications,
        userIdProvider: () => 'user-1',
      );

      final saved = await service.save(
        route: route,
        arriveByMinutes: 9 * 60,
        activeDays: {1, 2, 3, 4, 5},
        reminderEnabled: true,
        reminderMinutesBefore: 10,
      );

      expect(saved.estimatedDurationMinutes, 35);
      expect(saved.recommendedDepartureMinutes, 8 * 60 + 25);
      expect(repository.saves, 1);
      expect(notifications.cancellations, 1);
      expect(notifications.scheduled, same(saved));
    },
  );

  test('denied Android notification permission does not save', () async {
    final route = commuteRoute();
    final repository = MemoryCommuteRepository();
    final service = DailyCommuteService(
      repository: repository,
      apiService: CommuteApi(route),
      notificationService: CommuteNotifications(permission: false),
      userIdProvider: () => 'user-1',
    );

    await expectLater(
      service.save(
        route: route,
        arriveByMinutes: 9 * 60,
        activeDays: {1},
        reminderEnabled: true,
        reminderMinutesBefore: 10,
      ),
      throwsA(isA<NotificationPermissionException>()),
    );
    expect(repository.saves, 0);
  });

  test('reminder toggle and delete update notification lifecycle', () async {
    final repository = MemoryCommuteRepository();
    final notifications = CommuteNotifications();
    final service = DailyCommuteService(
      repository: repository,
      apiService: CommuteApi(commuteRoute()),
      notificationService: notifications,
      userIdProvider: () => 'user-1',
    );
    final commute = DailyCommute(
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'TAR UMT',
      arriveByMinutes: 9 * 60,
      activeDays: const {1, 2, 3, 4, 5},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
    );
    repository.value = commute;

    final disabled = await service.setReminderEnabled(commute, false);
    expect(disabled.reminderEnabled, isFalse);
    expect(notifications.cancellations, 1);
    expect(notifications.scheduled, isNull);

    final enabled = await service.setReminderEnabled(disabled, true);
    expect(enabled.reminderEnabled, isTrue);
    expect(notifications.cancellations, 2);
    expect(notifications.scheduled, same(enabled));

    await service.delete();
    expect(repository.value, isNull);
    expect(notifications.cancellations, 3);
  });

  testWidgets('Daily Commute settings fits a phone screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final route = commuteRoute();
    final service = DailyCommuteService(
      repository: MemoryCommuteRepository(),
      apiService: CommuteApi(route),
      notificationService: CommuteNotifications(),
      userIdProvider: () => 'user-1',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DailyCommuteSettingsScreen(
          service: service,
          savedRoutesRepository: MemorySavedRoutes(route),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Daily Commute'), findsOneWidget);
    expect(find.byKey(const Key('commute-route')), findsOneWidget);
    expect(find.byKey(const Key('save-daily-commute')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
