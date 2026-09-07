import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/screens/personal_travel.dart';
import 'package:nextroute_assignment/services/api_service.dart';
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
  Future<void> cancelDailyCommuteNotifications(DailyCommute commute) async =>
      cancellations++;

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

  test('calculates the next real reminder date and time', () {
    final commute = DailyCommute(
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'TAR UMT',
      arriveByMinutes: 9 * 60,
      activeDays: const {DateTime.monday, DateTime.wednesday},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 35,
    );

    expect(
      commute.nextReminderAfter(DateTime(2026, 9, 7, 8, 16)),
      DateTime(2026, 9, 9, 8, 15),
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
      arriveByMinutes: 10 * 60,
      activeDays: const {DateTime.monday},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
      estimatedDurationMinutes: 30,
    );
    final nearer = first.copyWith(
      id: 'nearer',
      destination: 'Campus',
      arriveByMinutes: 9 * 60,
    );
    final disabled = first.copyWith(
      id: 'disabled',
      arriveByMinutes: 8 * 60,
      reminderEnabled: false,
    );

    final next = DailyCommuteService.nextReminder([
      first,
      disabled,
      nearer,
    ], DateTime(2026, 9, 7, 7));
    expect(next!.commute.id, 'nearer');
    expect(next.time, DateTime(2026, 9, 7, 8, 20));
  });

  test('each reminder and weekday receives a unique notification ID', () {
    final notifications = LocalPushNotificationService();
    final first = DailyCommute(
      id: 'reminder-a',
      userId: 'user-1',
      savedRouteId: 'route-1',
      origin: 'Home',
      destination: 'Office',
      arriveByMinutes: 9 * 60,
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
      arriveByMinutes: 9 * 60,
      activeDays: {1, 3, 5},
      reminderEnabled: true,
      reminderMinutesBefore: 10,
    );
    await service.save(
      route: route,
      arriveByMinutes: 18 * 60,
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
      arriveByMinutes: 9 * 60,
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
        arriveByMinutes: 9 * 60,
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
    await tester.tap(find.byKey(const Key('commute-arrive-by')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('arrive-hour-wheel')), findsOneWidget);
    expect(find.byKey(const Key('arrive-minute-wheel')), findsOneWidget);
    expect(find.byKey(const Key('arrive-period-wheel')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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
    expect(find.text('Home → Office'), findsWidgets);
  });

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
    await tester.ensureVisible(find.byKey(const Key('save-daily-commute')));
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
          arriveByMinutes: 9 * 60,
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
          arriveByMinutes: 18 * 60,
          activeDays: const {1, 3, 5},
          reminderEnabled: false,
          reminderMinutesBefore: 15,
          estimatedDurationMinutes: 35,
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
