import 'dart:convert';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/screens/favourite_routes.dart';
import 'package:nextroute_assignment/screens/journey_planning.dart';
import 'package:nextroute_assignment/screens/personal_travel.dart';
import 'package:nextroute_assignment/services/api_service.dart';
import 'package:nextroute_assignment/services/personal_travel_service.dart';

StationModel station(String name, List<String> ids) => StationModel(
  ids: ids,
  name: name,
  lines: {'Kelana Jaya'},
  category: 'Rail',
  lat: 3.1,
  lon: 101.7,
);

SavedRoute sampleRoute({
  String name = 'Work',
  List<String> ids = const ['rail_b', 'rail_a'],
  String signature = 'DIR_rail_KJ',
}) => SavedRoute(
  id: 'saved-1',
  name: name,
  origin: station('KL SENTRAL', ids),
  destination: station('KLCC', ['rail_c']),
  signature: signature,
  lineName: 'Kelana Jaya',
);

TravelHistoryEntry trip(
  String origin,
  String destination,
  DateTime createdAt,
) => TravelHistoryEntry(
  origin: origin,
  destination: destination,
  fare: 2.5,
  currency: 'MYR',
  departureTime: '08:00',
  createdAt: createdAt,
  lineName: 'Kelana Jaya',
);

class MemoryRoutes implements SavedRoutesRepository {
  List<SavedRoute> routes = [];
  bool failLoad = false;
  bool failSave = false;
  bool failMutation = false;

  @override
  Future<List<SavedRoute>> load() async {
    if (failLoad) throw StateError('Offline');
    return routes.toList();
  }

  @override
  Future<int> count() async => routes.length;

  @override
  Future<void> save(SavedRoute route) async {
    if (failSave) throw StateError('Offline');
    routes.add(
      SavedRoute(
        id: route.id ?? 'saved-${routes.length + 1}',
        name: route.name,
        origin: route.origin,
        destination: route.destination,
        signature: route.signature,
        lineName: route.lineName,
      ),
    );
  }

  @override
  Future<void> rename(String id, String name) async {
    if (failMutation) throw StateError('Offline');
    routes = [
      for (final route in routes)
        if (route.id == id) sampleRoute(name: name) else route,
    ];
  }

  @override
  Future<void> delete(String id) async {
    if (failMutation) throw StateError('Offline');
    routes.removeWhere((route) => route.id == id);
  }
}

class MemoryPlaces implements SavedPlacesRepository {
  MemoryPlaces([Iterable<SavedPlace> initial = const []]) {
    places = {for (final place in initial) place.type: place};
  }

  late Map<SavedPlaceType, SavedPlace> places;

  @override
  Future<List<SavedPlace>> load() async => places.values.toList();

  @override
  Future<SavedPlace> upsert(SavedPlace place) async {
    places[place.type] = place;
    return place;
  }

  @override
  Future<void> delete(SavedPlaceType type) async => places.remove(type);
}

class ProfileServiceStub implements PersonalTravelService {
  ProfileServiceStub({this.history = const [], this.deleteAccountError});

  final List<TravelHistoryEntry> history;
  final Object? deleteAccountError;
  int deleteAccountCalls = 0;

  @override
  Future<PersonalProfile> loadProfile({String? confirmedEmail}) async =>
      PersonalProfile(
        displayName: 'Tester',
        email: confirmedEmail ?? 'tester@example.com',
        phoneNumber: '',
      );

  @override
  Future<List<TravelHistoryEntry>> loadTravelHistory({int limit = 100}) async =>
      history;

  @override
  Future<void> updateProfile({
    String? displayName,
    String? phoneNumber,
  }) async {}

  @override
  Future<String> uploadAvatar(
    Uint8List bytes, {
    required String contentType,
  }) async => 'https://example.com/avatar.jpg';

  @override
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    PasswordCodeLogin? passwordLogin,
  }) async {}

  @override
  Future<void> deleteAccount({required String confirmation}) async {
    expect(confirmation, 'DELETE');
    deleteAccountCalls++;
    if (deleteAccountError case final error?) throw error;
  }
}

class PlanningApi extends ApiService {
  List<StationModel> stations = [
    station('CURRENT ORIGIN', ['rail_a']),
    station('CURRENT DESTINATION', ['rail_c']),
  ];
  List<Map<String, dynamic>> results = [
    {
      'sig': 'OTHER',
      'name': 'Other line',
      'duration': '30 min',
      'fare': 'RM 5.00',
      'scheduledDepart': '12:00',
      'legs': [
        {'mode': 'Rail', 'name': 'Other line'},
      ],
    },
    {
      'sig': 'DIR_rail_KJ',
      'name': 'Kelana Jaya',
      'duration': '10 min',
      'fare': 'RM 2.00',
      'scheduledDepart': '13:00',
      'legs': [
        {'mode': 'Rail', 'name': 'Kelana Jaya'},
      ],
    },
  ];
  int searches = 0;
  StationModel? requestedOrigin;

  @override
  Future<List<StationModel>> loadAllStations() async => stations;

  @override
  Future<List<Map<String, dynamic>>> findRoutes(
    StationModel origin,
    StationModel destination,
  ) async {
    searches++;
    requestedOrigin = origin;
    return results;
  }
}

Future<void> launch(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  test('saved place keeps station data and resolves current GTFS IDs', () {
    final original = SavedPlace(
      type: SavedPlaceType.home,
      station: station('PV128 Setapak', ['old-id']),
    );
    final payload = original.toUpsert('user-1');
    final restored = SavedPlace.fromJson(payload);
    final current = station('Setapak station', ['old-id', 'new-id']);

    expect(payload['place_type'], 'home');
    expect(payload['latitude'], original.station.lat);
    expect(restored.station.ids, ['old-id']);
    expect(restored.resolveStation([current]), same(current));
  });

  testWidgets('Saved Places can add, edit and remove a station', (
    tester,
  ) async {
    final repository = MemoryPlaces();
    final api = PlanningApi();
    await launch(
      tester,
      SavedPlacesScreen(repository: repository, apiService: api),
    );

    expect(find.text('Not set'), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('set-saved-place-home')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CURRENT ORIGIN'));
    await tester.pumpAndSettle();
    expect(
      repository.places[SavedPlaceType.home]!.station.name,
      'CURRENT ORIGIN',
    );
    expect(find.text('CURRENT ORIGIN'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(repository.places.containsKey(SavedPlaceType.home), isFalse);
  });

  testWidgets('Journey Planning selects a Saved Place as the origin', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PlanningApi();
    final home = SavedPlace(
      type: SavedPlaceType.home,
      station: api.stations.first,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPlanningScreen(
          apiService: api,
          savedRoutesRepository: MemoryRoutes(),
          savedPlacesRepository: MemoryPlaces([home]),
          authenticate: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Origin Location'));
    await tester.pumpAndSettle();
    expect(find.text('SAVED PLACES'), findsOneWidget);
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('CURRENT ORIGIN'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('smart routine uses the most frequent route from the last 30 days', () {
    final now = DateTime(2026, 9, 6, 12);
    final suggestion = SmartRoutineService.detect(
      now: now,
      history: [
        trip('PV128 Setapak', 'TAR UMT', DateTime(2026, 9, 1)),
        trip(' pv128  setapak ', 'tar umt', DateTime(2026, 9, 3)),
        trip('PV128 Setapak', 'TAR UMT', DateTime(2026, 9, 5)),
        trip('Old', 'Route', DateTime(2026, 7, 1)),
        trip('KLCC', 'KL Sentral', DateTime(2026, 9, 2)),
        trip('KLCC', 'KL Sentral', DateTime(2026, 9, 4)),
        trip('KLCC', 'KL Sentral', DateTime(2026, 9, 5)),
        trip('KLCC', 'KL Sentral', DateTime(2026, 9, 6)),
      ],
    );

    expect(suggestion!.origin, 'KLCC');
    expect(suggestion.destination, 'KL Sentral');
    expect(suggestion.tripCount, 4);
    expect(suggestion.commonWeekdays, {3, 5, 6, 7});
  });

  test('smart routine is hidden for the configured commute', () {
    final now = DateTime(2026, 9, 6, 12);
    final history = [
      trip('Home', 'Campus', DateTime(2026, 9, 1)),
      trip('Home', 'Campus', DateTime(2026, 9, 2)),
      trip('Home', 'Campus', DateTime(2026, 9, 3)),
    ];

    expect(
      SmartRoutineService.detect(
        now: now,
        history: history,
        configuredCommutes: const [
          DailyCommuteRoute(origin: ' home ', destination: 'CAMPUS'),
        ],
      ),
      isNull,
    );
  });

  test('smart routine reuses an existing favourite route', () async {
    final route = sampleRoute();
    final repository = MemoryRoutes()..routes = [route];
    final service = SmartRoutineService(repository, apiService: PlanningApi());
    final suggestion = RoutineSuggestion(
      origin: route.origin.name.toLowerCase(),
      destination: route.destination.name,
      tripCount: 3,
      commonWeekdays: const {1, 3, 5},
      mostRecentTrip: DateTime(2026, 9, 5),
    );

    expect(await service.findOrCreateFavourite(suggestion), same(route));
    expect(repository.routes, hasLength(1));
  });

  test(
    'smart routine creates a favourite through existing route services',
    () async {
      final repository = MemoryRoutes();
      final service = SmartRoutineService(
        repository,
        apiService: PlanningApi(),
      );
      final saved = await service.findOrCreateFavourite(
        RoutineSuggestion(
          origin: 'CURRENT ORIGIN',
          destination: 'CURRENT DESTINATION',
          tripCount: 3,
          commonWeekdays: const {1, 3, 5},
          mostRecentTrip: DateTime(2026, 9, 5),
        ),
      );

      expect(saved.id, isNotNull);
      expect(saved.origin.name, 'CURRENT ORIGIN');
      expect(saved.destination.name, 'CURRENT DESTINATION');
      expect(repository.routes, hasLength(1));
    },
  );

  testWidgets(
    'dashboard shows and dismisses a smart routine for this session',
    (tester) async {
      final now = DateTime.now();
      await launch(
        tester,
        PersonalTravelScreen(
          service: ProfileServiceStub(
            history: [
              trip(
                'PV128 Setapak',
                'TAR UMT',
                now.subtract(const Duration(days: 1)),
              ),
              trip(
                'PV128 Setapak',
                'TAR UMT',
                now.subtract(const Duration(days: 2)),
              ),
              trip(
                'PV128 Setapak',
                'TAR UMT',
                now.subtract(const Duration(days: 3)),
              ),
            ],
          ),
          savedRoutesRepository: MemoryRoutes(),
        ),
      );

      expect(find.text('SMART ROUTINE SUGGESTION'), findsOneWidget);
      expect(find.text('3 trips in the last 30 days'), findsOneWidget);
      await tester.tap(find.byKey(const Key('dismiss-routine-suggestion')));
      await tester.pump();
      expect(find.text('SMART ROUTINE SUGGESTION'), findsNothing);
    },
  );

  test(
    'saved payload is JSON safe and restores station IDs for replanning',
    () {
      final original = sampleRoute();
      final payload =
          jsonDecode(jsonEncode(original.toInsert('user-a')))
              as Map<String, dynamic>;
      final restored = SavedRoute.fromJson({...payload, 'id': 'saved-1'});
      expect(restored.origin.ids, ['rail_a', 'rail_b']);
      expect(restored.destination.ids, ['rail_c']);
      expect(restored.routeKey, original.routeKey);
      expect(payload['user_id'], 'user-a');
      expect(payload.containsKey('scheduledDepart'), false);
    },
  );

  test(
    'route identity ignores title and ID ordering, but includes direction and route',
    () {
      final original = sampleRoute();
      expect(
        sampleRoute(name: 'Renamed', ids: ['rail_a', 'rail_b']).routeKey,
        original.routeKey,
      );
      expect(
        sampleRoute(signature: 'OTHER').routeKey,
        isNot(original.routeKey),
      );
      final reverse = SavedRoute(
        name: 'Return',
        origin: original.destination,
        destination: original.origin,
        signature: original.signature,
        lineName: original.lineName,
      );
      expect(reverse.routeKey, isNot(original.routeKey));
    },
  );

  test(
    'resolves current GTFS IDs and does not guess a replacement station',
    () {
      final saved = sampleRoute();
      final current = station('New station label', ['rail_b', 'rail_new']);
      expect(saved.resolveOrigin([current])!.ids, ['rail_b', 'rail_new']);
      expect(
        saved.resolveOrigin([
          station('KL SENTRAL', ['unrelated']),
        ]),
        isNull,
      );
    },
  );

  testWidgets('load failure can retry and show empty favourites', (
    tester,
  ) async {
    final repository = MemoryRoutes()..failLoad = true;
    await launch(tester, FavouriteRoutesScreen(repository: repository));
    expect(
      find.text('Unable to load favourites. Please try again.'),
      findsOneWidget,
    );
    repository.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('No favourite routes yet'), findsOneWidget);
  });

  testWidgets(
    'rename rejects blank titles; failed deletion preserves the route',
    (tester) async {
      final repository = MemoryRoutes()..routes = [sampleRoute()];
      await launch(tester, FavouriteRoutesScreen(repository: repository));
      await tester.tap(find.byTooltip('Route options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a route name.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'Office');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('Office'), findsOneWidget);
      repository.failMutation = true;
      await tester.tap(find.byTooltip('Route options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repository.routes, hasLength(1));
      expect(
        find.text('Unable to update favourites. Please try again.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Plan again returns the selected favourite', (tester) async {
    final repository = MemoryRoutes()..routes = [sampleRoute()];
    SavedRoute? result;
    await launch(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.push<SavedRoute>(
                context,
                MaterialPageRoute(
                  builder: (_) => FavouriteRoutesScreen(repository: repository),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan again'));
    await tester.pumpAndSettle();
    expect(result!.routeKey, sampleRoute().routeKey);
  });

  testWidgets(
    'replanning uses current stations, selects saved route and retries a failed save',
    (tester) async {
      final api = PlanningApi();
      final repository = MemoryRoutes()..failSave = true;
      await launch(
        tester,
        JourneyPlanningScreen(
          savedRoute: sampleRoute(),
          apiService: api,
          savedRoutesRepository: repository,
          authenticate: (_) async => true,
        ),
      );
      expect(api.searches, 1);
      expect(api.requestedOrigin!.ids, ['rail_a']);
      expect(find.text('10 min'), findsWidgets);
      await tester.ensureVisible(find.text('Save route'));
      await tester.tap(find.text('Save route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Unable to save route. Please try again.'),
        findsOneWidget,
      );
      expect(repository.routes, isEmpty);
      repository.failSave = false;
      await tester.tap(find.text('Save route'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repository.routes.single.signature, 'DIR_rail_KJ');
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('missing saved station asks for new locations without searching', (
    tester,
  ) async {
    final api = PlanningApi()..stations = [];
    await launch(
      tester,
      JourneyPlanningScreen(
        savedRoute: sampleRoute(),
        apiService: api,
        authenticate: (_) async => false,
      ),
    );
    expect(api.searches, 0);
    expect(
      find.text(
        'A saved station is no longer available. Please select your locations again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'guest can plan but cancelling sign-in does not save or lose the route',
    (tester) async {
      final api = PlanningApi();
      final repository = MemoryRoutes();
      var prompts = 0;
      await launch(
        tester,
        JourneyPlanningScreen(
          savedRoute: sampleRoute(),
          apiService: api,
          savedRoutesRepository: repository,
          authenticate: (_) async {
            prompts++;
            return false;
          },
        ),
      );
      expect(api.searches, 1);
      await tester.ensureVisible(find.text('Save route'));
      await tester.tap(find.text('Save route'));
      await tester.pumpAndSettle();
      expect(prompts, 1);
      expect(repository.routes, isEmpty);
      expect(find.text('Route name'), findsNothing);
      expect(find.text('Save route'), findsOneWidget);
    },
  );

  testWidgets('a previously saved search result shows a red heart', (
    tester,
  ) async {
    final repository = MemoryRoutes()..routes = [sampleRoute()];
    await launch(
      tester,
      JourneyPlanningScreen(
        savedRoute: sampleRoute(),
        apiService: PlanningApi(),
        savedRoutesRepository: repository,
        authenticate: (_) async => true,
      ),
    );

    final heart = find.byTooltip('Saved route');
    expect(heart, findsOneWidget);
    final icon = tester.widget<Icon>(
      find.descendant(of: heart, matching: find.byIcon(Icons.favorite)),
    );
    expect(icon.color, const Color(0xFFE11D48));
  });

  testWidgets('Add Route switches to the main Journey tab when available', (
    tester,
  ) async {
    var openedJourneyTab = false;
    await launch(
      tester,
      PersonalTravelScreen(
        service: ProfileServiceStub(),
        savedRoutesRepository: MemoryRoutes(),
        onOpenJourneyPlanning: () => openedJourneyTab = true,
      ),
    );

    await tester.tap(find.text('Favourite Routes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Route'));
    await tester.pumpAndSettle();

    expect(openedJourneyTab, isTrue);
    expect(find.text('Journey Planning'), findsNothing);
  });

  testWidgets('dashboard Home switches to the first Journey tab', (
    tester,
  ) async {
    var openedJourneyTab = false;
    await launch(
      tester,
      PersonalTravelScreen(
        service: ProfileServiceStub(),
        savedRoutesRepository: MemoryRoutes(),
        onOpenJourneyPlanning: () => openedJourneyTab = true,
      ),
    );

    await tester.tap(find.byKey(const Key('dashboard-home')));
    await tester.pumpAndSettle();

    expect(openedJourneyTab, isTrue);
  });

  testWidgets('profile shows a default avatar and photo picker button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await launch(
      tester,
      PersonalTravelScreen(
        service: ProfileServiceStub(),
        savedRoutesRepository: MemoryRoutes(),
      ),
    );

    expect(find.text('Dashboard'), findsOneWidget);
    await tester.tap(find.byKey(const Key('open-my-profile')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('profile-avatar')), findsOneWidget);
    expect(find.text('T'), findsWidgets);
    expect(find.byKey(const Key('change-profile-photo')), findsOneWidget);

    await tester.tap(find.byKey(const Key('close-profile-page')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-travel-history')));
    await tester.pumpAndSettle();

    expect(find.text('Travel History'), findsOneWidget);
    expect(find.text('No trips found'), findsOneWidget);
  });

  testWidgets('delete account requires typing DELETE before confirmation', (
    tester,
  ) async {
    final service = ProfileServiceStub();
    var returnedToLogin = false;
    await launch(
      tester,
      PersonalTravelScreen(
        service: service,
        savedRoutesRepository: MemoryRoutes(),
        onAccountDeleted: () => returnedToLogin = true,
      ),
    );

    await tester.tap(find.byKey(const Key('open-my-profile')));
    await tester.pumpAndSettle();
    final deleteAction = find.byKey(const Key('delete-account-action'));
    await tester.ensureVisible(deleteAction);
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();

    expect(find.text('Delete Account?'), findsOneWidget);
    final confirmButton = find.byKey(const Key('confirm-delete-account'));
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation')),
      'DELETE',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirmButton).onPressed, isNotNull);
    await tester.tap(confirmButton);
    await tester.pumpAndSettle();

    expect(service.deleteAccountCalls, 1);
    expect(returnedToLogin, isTrue);
  });

  testWidgets('failed account deletion keeps the user on the profile', (
    tester,
  ) async {
    final service = ProfileServiceStub(
      deleteAccountError: StateError(
        'Account deletion failed. Your account is still available.',
      ),
    );
    var returnedToLogin = false;
    await launch(
      tester,
      PersonalTravelScreen(
        service: service,
        savedRoutesRepository: MemoryRoutes(),
        onAccountDeleted: () => returnedToLogin = true,
      ),
    );

    await tester.tap(find.byKey(const Key('open-my-profile')));
    await tester.pumpAndSettle();
    final deleteAction = find.byKey(const Key('delete-account-action'));
    await tester.ensureVisible(deleteAction);
    await tester.tap(deleteAction);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('delete-account-confirmation')),
      'DELETE',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('confirm-delete-account')));
    await tester.pumpAndSettle();

    expect(service.deleteAccountCalls, 1);
    expect(returnedToLogin, isFalse);
    expect(find.text('My Profile'), findsOneWidget);
    expect(
      find.text('Account deletion failed. Your account is still available.'),
      findsOneWidget,
    );
  });
}
