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
    routes.add(route);
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

class ProfileServiceStub implements PersonalTravelService {
  @override
  Future<PersonalProfile> loadProfile({String? confirmedEmail}) async =>
      PersonalProfile(
        displayName: 'Tester',
        email: confirmedEmail ?? 'tester@example.com',
        phoneNumber: '',
      );

  @override
  Future<List<TravelHistoryEntry>> loadTravelHistory({int limit = 100}) async =>
      const [];

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
}
