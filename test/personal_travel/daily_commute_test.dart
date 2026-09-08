import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/screens/personal_travel.dart';
import 'package:nextroute_assignment/services/api_service.dart';
import 'package:nextroute_assignment/services/gtfs_route_timetable.dart';
import 'package:nextroute_assignment/services/notification_service.dart';
import 'package:nextroute_assignment/services/personal_travel_service.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class MemoryCommuteRepository implements DailyCommuteRepository {
  final List<DailyCommute> values = [];
  int saves = 0;

  DailyCommute? get value => values.firstOrNull;

  set value(DailyCommute? commute) {
    values
      ..clear()
      ..addAll(
        commute == null
            ? const []
            : [commute.id == null ? commute.copyWith(id: 'existing') : commute],
      );
  }

  @override
  Future<List<DailyCommute>> loadAll() async => values.toList();

  @override
  Future<DailyCommute> upsert(DailyCommute commute) async {
    saves++;
    final saved = commute.id == null
        ? commute.copyWith(id: 'commute-$saves')
        : commute;
    values.removeWhere((item) => item.id == saved.id);
    values.add(saved);
    return saved;
  }

  @override
  Future<void> delete(String id) async =>
      values.removeWhere((commute) => commute.id == id);
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

class MutableSavedRoutes implements SavedRoutesRepository {
  MutableSavedRoutes(this.routes);

  final List<SavedRoute> routes;

  @override
  Future<int> count() async => routes.length;

  @override
  Future<void> delete(String id) async =>
      routes.removeWhere((route) => route.id == id);

  @override
  Future<List<SavedRoute>> load() async => routes.toList();

  @override
  Future<void> rename(String id, String name) async {}

  @override
  Future<void> save(SavedRoute route) async => routes.add(route);
}

class CommuteApi extends ApiService {
  CommuteApi(
    this.route, {
    this.duration = '35 min',
    this.serviceAvailable = true,
    this.nextDepartureMinutes,
  });

  final SavedRoute route;
  final String duration;
  final bool serviceAvailable;
  final int? nextDepartureMinutes;

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

  @override
  Future<RouteServiceAvailability> validateRouteTimetable({
    required StationModel origin,
    required StationModel destination,
    required List<String> serviceSequence,
    required Set<int> weekdays,
    required int departureTimeMinutes,
    DateTime? referenceDate,
  }) async {
    final reference = referenceDate ?? DateTime(2026, 9, 7);
    return RouteServiceAvailability(
      days: [
        for (final weekday in weekdays)
          RouteServiceDayAvailability(
            weekday: weekday,
            date: reference.add(
              Duration(days: (weekday - reference.weekday) % 7),
            ),
            isAvailable: serviceAvailable,
            departure: serviceAvailable
                ? DateTime(
                    reference.year,
                    reference.month,
                    reference.day,
                  ).add(Duration(minutes: departureTimeMinutes))
                : null,
            arrival: serviceAvailable
                ? DateTime(
                    reference.year,
                    reference.month,
                    reference.day,
                  ).add(Duration(minutes: departureTimeMinutes + 35))
                : null,
            nextDeparture: nextDepartureMinutes == null
                ? null
                : DateTime(
                    reference.year,
                    reference.month,
                    reference.day,
                  ).add(Duration(minutes: nextDepartureMinutes!)),
            nextArrival: nextDepartureMinutes == null
                ? null
                : DateTime(
                    reference.year,
                    reference.month,
                    reference.day,
                  ).add(Duration(minutes: nextDepartureMinutes! + 35)),
          ),
      ],
    );
  }
}

class CommuteNotifications extends LocalPushNotificationService {
  CommuteNotifications({this.permission = true});

  final bool permission;
  int cancellations = 0;
  int schedules = 0;
  DailyCommute? scheduled;

  @override
  bool get isSupported => true;

  @override
  Future<bool> requestPermission() async => permission;

  @override
  Future<void> cancelDailyCommuteNotifications(DailyCommute commute) async =>
      cancellations++;

  @override
  Future<void> scheduleDailyCommuteNotifications(DailyCommute commute) async {
    schedules++;
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

  test('normalizes Android timezone identifiers used by notifications', () {
    expect(
      LocalPushNotificationService.timezoneNameForDeviceIdentifier(
        'Asia/Kuala_Lumpur',
      ),
      'Asia/Singapore',
    );
    expect(
      LocalPushNotificationService.timezoneNameForDeviceIdentifier('GMT+08:00'),
      'Etc/GMT-8',
    );
    expect(
      LocalPushNotificationService.timezoneNameForDeviceIdentifier('UTC'),
      'Etc/UTC',
    );
  });

  test('calculates notification and arrival time from departure time', () {
    final commute = DailyCommute(
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'TAR UMT',
      departureTimeMinutes: 8 * 60 + 30,
      activeDays: const {1, 2, 3, 4, 5},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 30,
    );

    expect(commute.notificationTimeMinutes, 8 * 60 + 20);
    expect(commute.estimatedArrivalMinutes, 9 * 60);
  });

  test('uses the legacy database time field as departure time', () {
    final commute = DailyCommute.fromJson({
      'id': 'commute-1',
      'user_id': 'user-1',
      'saved_route_id': 'route-1',
      'origin': 'Home',
      'destination': 'TAR UMT',
      'arrive_by': '08:30:00',
      'active_days': [1, 2, 3, 4, 5],
      'reminder_enabled': true,
      'reminder_minutes_before': 10,
      'estimated_duration_minutes': 30,
    });

    expect(commute.departureTimeMinutes, 8 * 60 + 30);
    expect(commute.notificationTimeMinutes, 8 * 60 + 20);
    expect(commute.estimatedArrivalMinutes, 9 * 60);
    expect(commute.toUpsert()['arrive_by'], '08:30:00');
    expect(commute.hasServiceWarning, isFalse);
    expect(commute.toUpsert()['has_service_warning'], isFalse);
  });

  test('persists the Save Anyway service warning', () {
    final commute = DailyCommute.fromJson({
      'id': 'commute-1',
      'user_id': 'user-1',
      'saved_route_id': 'route-1',
      'origin': 'Home',
      'destination': 'TAR UMT',
      'arrive_by': '04:00:00',
      'active_days': [1],
      'reminder_enabled': true,
      'reminder_minutes_before': 10,
      'estimated_duration_minutes': 30,
      'has_service_warning': true,
    });

    expect(commute.hasServiceWarning, isTrue);
    expect(commute.toUpsert()['has_service_warning'], isTrue);
    expect(commute.departureTimeMinutes, 4 * 60);
  });

  test('moves an after-midnight commute reminder to the previous weekday', () {
    final commute = DailyCommute(
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'TAR UMT',
      departureTimeMinutes: 5,
      activeDays: const {DateTime.monday},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
    );

    expect(commute.notificationTimeMinutes, 23 * 60 + 55);
    expect(
      commute.notificationWeekdayForDepartureDay(DateTime.monday),
      DateTime.sunday,
    );
  });

  test('calculates the next real reminder date and time', () {
    final commute = DailyCommute(
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'TAR UMT',
      departureTimeMinutes: 9 * 60,
      activeDays: const {DateTime.monday, DateTime.wednesday},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
    );

    expect(
      commute.nextReminderAfter(DateTime(2026, 9, 7, 8, 51)),
      DateTime(2026, 9, 9, 8, 50),
    );
    expect(
      commute
          .copyWith(reminderEnabled: false)
          .nextReminderAfter(DateTime(2026, 9, 7)),
      isNull,
    );
  });

  test('selects the nearest upcoming enabled reminder from multiple', () {
    final first = DailyCommute(
      id: 'first',
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'Office',
      departureTimeMinutes: 10 * 60,
      activeDays: const {DateTime.monday},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 30,
    );
    final nearer = first.copyWith(
      id: 'nearer',
      destination: 'Campus',
      departureTimeMinutes: 9 * 60,
    );
    final disabled = first.copyWith(
      id: 'disabled',
      departureTimeMinutes: 8 * 60,
      reminderEnabled: false,
    );

    final next = DailyCommuteService.nextReminder([
      first,
      disabled,
      nearer,
    ], DateTime(2026, 9, 7, 7));
    expect(next!.commute.id, 'nearer');
    expect(next.time, DateTime(2026, 9, 7, 8, 50));
  });

  test('each reminder and weekday receives a unique notification ID', () {
    final notifications = LocalPushNotificationService();
    final first = DailyCommute(
      id: 'reminder-a',
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'Office',
      departureTimeMinutes: 9 * 60,
      activeDays: const {1, 2},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 30,
    );
    final second = first.copyWith(id: 'reminder-b');
    final ids = <int>{
      for (final commute in [first, second])
        for (final day in commute.activeDays)
          notifications.notificationId(commute, day),
    };
    expect(ids, hasLength(4));
  });

  test('saving a second reminder does not overwrite the first', () async {
    final route = commuteRoute();
    final repository = MemoryCommuteRepository();
    final service = DailyCommuteService(
      repository: repository,
      apiService: CommuteApi(route),
      notificationService: CommuteNotifications(),
      userIdProvider: () => 'user-1',
    );
    await service.save(
      route: route,
      departureTimeMinutes: 9 * 60,
      activeDays: {1, 3, 5},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
    );
    await service.save(
      route: route,
      departureTimeMinutes: 18 * 60,
      activeDays: {2, 4},
      reminderEnabled: false,
      reminderMinutesBefore: 15,
    );

    expect(await service.loadAll(), hasLength(2));
    expect(repository.values.map((item) => item.id).toSet(), hasLength(2));
  });

  test('identical Daily Commute settings are rejected', () async {
    final route = commuteRoute();
    final repository = MemoryCommuteRepository();
    repository.value = DailyCommute(
      id: 'existing',
      userId: 'user-1',
      savedRouteId: route.id,
      origin: route.origin.name,
      destination: route.destination.name,
      departureTimeMinutes: 9 * 60,
      activeDays: const {1, 3, 5},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
    );
    final service = DailyCommuteService(
      repository: repository,
      apiService: CommuteApi(route),
      notificationService: CommuteNotifications(),
      userIdProvider: () => 'user-1',
    );

    await expectLater(
      service.save(
        route: route,
        departureTimeMinutes: 9 * 60,
        activeDays: {5, 1, 3},
        reminderEnabled: true,
        reminderMinutesBefore: 10,
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'An identical Daily Commute already exists.',
        ),
      ),
    );
    expect(repository.saves, 0);
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
        departureTimeMinutes: 9 * 60,
        activeDays: {1, 2, 3, 4, 5},
        reminderEnabled: true,
        reminderMinutesBefore: 10,
      );

      expect(saved.estimatedDurationMinutes, 35);
      expect(saved.estimatedArrivalMinutes, 9 * 60 + 35);
      expect(repository.saves, 1);
      expect(notifications.cancellations, 1);
      expect(notifications.scheduled, same(saved));
    },
  );

  test(
    'save supports an independent commute without a favourite route',
    () async {
      final repository = MemoryCommuteRepository();
      final notifications = CommuteNotifications();
      final service = DailyCommuteService(
        repository: repository,
        apiService: CommuteApi(commuteRoute()),
        notificationService: notifications,
        userIdProvider: () => 'user-1',
      );

      final saved = await service.save(
        route: null,
        origin: 'Home',
        destination: 'Office',
        estimatedDurationMinutes: 35,
        departureTimeMinutes: 9 * 60,
        activeDays: {1, 2, 3},
        reminderEnabled: false,
        reminderMinutesBefore: 10,
      );

      expect(saved.savedRouteId, isNull);
      expect(saved.origin, 'Home');
      expect(saved.destination, 'Office');
      expect(saved.estimatedDurationMinutes, 35);
      expect(notifications.scheduled, isNull);
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
        departureTimeMinutes: 9 * 60,
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
      departureTimeMinutes: 9 * 60,
      activeDays: const {1, 2, 3, 4, 5},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
    );
    repository.value = commute;

    final disabled = await service.setReminderEnabled(repository.value!, false);
    expect(disabled.reminderEnabled, isFalse);
    expect(notifications.cancellations, 1);
    expect(notifications.scheduled, isNull);

    final enabled = await service.setReminderEnabled(disabled, true);
    expect(enabled.reminderEnabled, isTrue);
    expect(notifications.cancellations, 2);
    expect(notifications.scheduled, same(enabled));

    await service.delete(enabled);
    expect(repository.value, isNull);
    expect(notifications.cancellations, 3);
  });

  test('notification sync refreshes existing enabled reminders', () async {
    final notifications = CommuteNotifications();
    final service = DailyCommuteService(
      repository: MemoryCommuteRepository(),
      apiService: CommuteApi(commuteRoute()),
      notificationService: notifications,
      userIdProvider: () => 'user-1',
    );
    final enabled = DailyCommute(
      id: 'enabled',
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'Office',
      departureTimeMinutes: 8 * 60 + 30,
      activeDays: const {DateTime.monday},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 30,
    );
    final disabled = enabled.copyWith(id: 'disabled', reminderEnabled: false);

    await service.syncNotifications([enabled, disabled]);

    expect(notifications.cancellations, 2);
    expect(notifications.schedules, 1);
    expect(notifications.scheduled, same(enabled));
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
    expect(find.text('Departure Time'), findsOneWidget);
    expect(find.text('Notification time'), findsOneWidget);
    expect(find.text('8:50 AM'), findsOneWidget);
    expect(find.byKey(const Key('commute-route')), findsOneWidget);
    await tester.tap(find.byKey(const Key('commute-departure-time')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('departure-hour-wheel')), findsOneWidget);
    expect(find.byKey(const Key('departure-minute-wheel')), findsOneWidget);
    expect(find.byKey(const Key('departure-period-wheel')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-daily-commute')),
      400,
    );
    expect(find.byKey(const Key('save-daily-commute')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an unavailable GTFS route can be saved with a warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final route = commuteRoute();
    final repository = MemoryCommuteRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DailyCommuteSettingsScreen(
          service: DailyCommuteService(
            repository: repository,
            apiService: CommuteApi(
              route,
              serviceAvailable: false,
              nextDepartureMinutes: 10 * 60 + 20,
            ),
            notificationService: CommuteNotifications(),
            userIdProvider: () => 'user-1',
          ),
          savedRoutesRepository: MemorySavedRoutes(route),
          initialRoute: route,
          initialActiveDays: const {DateTime.monday},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('commute-service-unavailable')),
      findsOneWidget,
    );
    expect(
      find.textContaining('No scheduled service around 9:00 AM'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Next available service: 10:20 AM'),
      findsOneWidget,
    );
    expect(find.text('Estimated arrival'), findsNothing);

    await tester.scrollUntilVisible(
      find.byKey(const Key('save-daily-commute')),
      400,
    );
    await tester.tap(find.byKey(const Key('save-daily-commute')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('choose-another-commute-time')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('save-commute-anyway')), findsOneWidget);

    await tester.tap(find.byKey(const Key('choose-another-commute-time')));
    await tester.pumpAndSettle();
    expect(repository.value, isNull);

    await tester.tap(find.byKey(const Key('save-daily-commute')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-commute-anyway')));
    await tester.pumpAndSettle();

    expect(repository.value!.departureTimeMinutes, 9 * 60);
    expect(repository.value!.hasServiceWarning, isTrue);
  });

  testWidgets('editing to a valid departure removes the saved warning', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final route = commuteRoute();
    final repository = MemoryCommuteRepository();
    repository.value = DailyCommute(
      id: 'existing',
      userId: 'user-1',
      savedRouteId: route.id,
      origin: route.origin.name,
      destination: route.destination.name,
      departureTimeMinutes: 9 * 60,
      activeDays: const {DateTime.monday},
      reminderEnabled: false,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
      hasServiceWarning: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DailyCommuteSettingsScreen(
          service: DailyCommuteService(
            repository: repository,
            apiService: CommuteApi(route),
            notificationService: CommuteNotifications(),
            userIdProvider: () => 'user-1',
          ),
          savedRoutesRepository: MemorySavedRoutes(route),
          initialCommute: repository.value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('commute-service-available')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('save-daily-commute')),
      400,
    );
    await tester.tap(find.byKey(const Key('save-daily-commute')));
    await tester.pumpAndSettle();

    expect(repository.value!.hasServiceWarning, isFalse);
  });

  testWidgets('route picker can add and select a new favourite journey', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final first = commuteRoute();
    final second = SavedRoute(
      id: 'route-2',
      name: 'Work commute',
      origin: first.origin,
      destination: StationModel(
        ids: const ['office'],
        name: 'Office',
        lines: {'KJ'},
        category: 'Rail',
        lat: 3.2,
        lon: 101.2,
      ),
      signature: 'DIR_OFFICE',
      lineName: 'Kelana Jaya',
    );
    final routes = MutableSavedRoutes([first]);
    var openedJourneyPlanning = false;
    await tester.pumpWidget(
      MaterialApp(
        home: DailyCommuteSettingsScreen(
          service: DailyCommuteService(
            repository: MemoryCommuteRepository(),
            apiService: CommuteApi(first),
            notificationService: CommuteNotifications(),
            userIdProvider: () => 'user-1',
          ),
          savedRoutesRepository: routes,
          addFavouriteJourney: (_) async {
            openedJourneyPlanning = true;
            routes.routes.add(second);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Add New Favourite Journey'), findsOneWidget);
    await tester.tap(find.text('Add New Favourite Journey'));
    await tester.pumpAndSettle();

    expect(openedJourneyPlanning, isTrue);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    expect(find.text('Work commute'), findsWidgets);
    expect(find.text('Home → Office'), findsWidgets);
  });

  testWidgets(
    'a commute route can be selected in Journey Planning without a favourite',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = commuteRoute();
      final plannedRoute = SavedRoute(
        name: source.name,
        origin: source.origin,
        destination: source.destination,
        signature: source.signature,
        lineName: source.lineName,
      );
      final commuteRepository = MemoryCommuteRepository();
      final favourites = MutableSavedRoutes([]);

      await tester.pumpWidget(
        MaterialApp(
          home: DailyCommuteSettingsScreen(
            service: DailyCommuteService(
              repository: commuteRepository,
              apiService: CommuteApi(plannedRoute),
              notificationService: CommuteNotifications(),
              userIdProvider: () => 'user-1',
            ),
            savedRoutesRepository: favourites,
            chooseJourneyRoute: (_) async {
              favourites.routes.add(source);
              return plannedRoute;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('commute-origin')), findsNothing);
      expect(find.textContaining('No Favourite Routes yet.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('choose-commute-route')));
      await tester.pumpAndSettle();
      expect(find.text('Home → TAR UMT'), findsOneWidget);
      expect(find.byKey(const Key('commute-route')), findsOneWidget);
      expect(
        find.textContaining('independent from Favourite Routes'),
        findsNothing,
      );

      await tester.scrollUntilVisible(
        find.byKey(const Key('save-daily-commute')),
        400,
      );
      await tester.tap(find.byKey(const Key('save-daily-commute')));
      await tester.pumpAndSettle();

      expect(commuteRepository.value!.savedRouteId, isNull);
      expect(commuteRepository.value!.origin, 'Home');
      expect(commuteRepository.value!.destination, 'TAR UMT');
      expect(commuteRepository.value!.estimatedDurationMinutes, 35);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('routine suggestion prefills route and detected weekdays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final route = commuteRoute();
    final repository = MemoryCommuteRepository();
    final service = DailyCommuteService(
      repository: repository,
      apiService: CommuteApi(route),
      notificationService: CommuteNotifications(),
      userIdProvider: () => 'user-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: DailyCommuteSettingsScreen(
          service: service,
          savedRoutesRepository: MemorySavedRoutes(route),
          initialRoute: route,
          initialActiveDays: const {
            DateTime.monday,
            DateTime.wednesday,
            DateTime.friday,
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('save-daily-commute')),
      400,
    );
    await tester.tap(find.byKey(const Key('save-daily-commute')));
    await tester.pumpAndSettle();

    expect(repository.value!.savedRouteId, route.id);
    expect(repository.value!.activeDays, {1, 3, 5});
  });

  testWidgets('Smart Reminders overview lists multiple reminders', (
    tester,
  ) async {
    final route = commuteRoute();
    final repository = MemoryCommuteRepository()
      ..values.addAll([
        DailyCommute(
          id: 'morning',
          userId: 'user-1',
          savedRouteId: route.id,
          origin: 'Home',
          destination: 'Campus',
          departureTimeMinutes: 9 * 60,
          activeDays: const {1, 3, 5},
          reminderEnabled: true,
          reminderMinutesBefore: 10,
          estimatedDurationMinutes: 35,
        ),
        DailyCommute(
          id: 'evening',
          userId: 'user-1',
          savedRouteId: route.id,
          origin: 'Campus',
          destination: 'Home',
          departureTimeMinutes: 18 * 60,
          activeDays: const {1, 3, 5},
          reminderEnabled: false,
          reminderMinutesBefore: 15,
          estimatedDurationMinutes: 35,
          hasServiceWarning: true,
        ),
      ]);
    final service = DailyCommuteService(
      repository: repository,
      apiService: CommuteApi(route),
      notificationService: CommuteNotifications(),
      userIdProvider: () => 'user-1',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DailyCommuteOverviewSheet(
            service: service,
            savedRoutesRepository: MemorySavedRoutes(route),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home → Campus'), findsOneWidget);
    expect(find.text('Campus → Home'), findsOneWidget);
    expect(find.byType(Switch), findsNWidgets(2));
    expect(
      find.byKey(const Key('saved-commute-service-warning')),
      findsOneWidget,
    );
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets(
    'adding a favourite from Smart Reminders returns to the main Journey tab',
    (tester) async {
      final route = commuteRoute();
      final service = DailyCommuteService(
        repository: MemoryCommuteRepository(),
        apiService: CommuteApi(route),
        notificationService: CommuteNotifications(),
        userIdProvider: () => 'user-1',
      );
      var openedJourneyTab = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => FilledButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => DailyCommuteOverviewSheet(
                    service: service,
                    savedRoutesRepository: MemorySavedRoutes(route),
                    onOpenJourneyPlanning: () => openedJourneyTab = true,
                  ),
                ),
                child: const Text('Open reminders'),
              ),
            ),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.route),
                  label: 'Journey',
                ),
                NavigationDestination(
                  icon: Icon(Icons.person),
                  label: 'Profile',
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open reminders'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add New Favourite Journey'));
      await tester.pumpAndSettle();

      expect(openedJourneyTab, isTrue);
      expect(find.text('Smart Reminders'), findsNothing);
      expect(find.text('Daily Commute'), findsNothing);
      expect(find.byType(NavigationBar), findsOneWidget);
    },
  );
}
