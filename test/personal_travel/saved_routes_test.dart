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
  String lineName = 'Kelana Jaya',
  List<String> serviceSequence = const [],
  List<String> transportModes = const [],
}) => SavedRoute(
  id: 'saved-1',
  name: name,
  origin: station('KL SENTRAL', ids),
  destination: station('KLCC', ['rail_c']),
  signature: signature,
  lineName: lineName,
  serviceSequence: serviceSequence,
  transportModes: transportModes,
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
        serviceSequence: route.serviceSequence,
        transportModes: route.transportModes,
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
  StationModel? requestedDestination;
  String? requiredOriginId;
  String? requiredDestinationId;

  @override
  Future<List<StationModel>> loadAllStations() async => stations;

  @override
  Future<List<Map<String, dynamic>>> findRoutes(
    StationModel origin,
    StationModel destination,
  ) async {
    searches++;
    requestedOrigin = origin;
    requestedDestination = destination;
    final expectedOriginId = requiredOriginId;
    if (expectedOriginId != null && !origin.ids.contains(expectedOriginId)) {
      return [];
    }
    final expectedDestinationId = requiredDestinationId;
    if (expectedDestinationId != null &&
        !destination.ids.contains(expectedDestinationId)) {
      return [];
    }
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
  test('travel history restores the saved journey details', () {
    final entry = TravelHistoryEntry.fromJson({
      'origin': 'TAMAN BUNGA RAYA',
      'destination': 'UTAR PINTU 2',
      'fare': 5.25,
      'currency': 'MYR',
      'duration_minutes': 32,
      'departure_time': '09:37',
      'estimated_arrival_time': '10:09',
      'created_at': '2026-09-07T09:37:00+08:00',
      'origin_station': {
        'ids': ['bus_1utama'],
        'name': '1 UTAMA',
        'lines': ['250'],
        'category': 'Bus',
        'lat': 3.15,
        'lon': 101.61,
      },
      'destination_station': {
        'ids': ['rail_klcc'],
        'name': 'KLCC',
        'lines': ['Kelana Jaya'],
        'category': 'Rail',
        'lat': 3.16,
        'lon': 101.71,
      },
      'route_signature': 'DIR_250_KJ',
      'line_name': '250 via Wangsa Maju',
      'transit_steps': [
        {
          'mode': 'Bus',
          'name': '250 via Wangsa Maju',
          'duration': '27 min',
          'desc': 'Board at Taman Bunga Raya',
        },
      ],
    });

    expect(entry.durationMinutes, 32);
    expect(entry.estimatedArrivalTime, '10:09');
    expect(entry.transitSteps, hasLength(1));
    expect(entry.hasReusableRoute, isTrue);
    expect(entry.originStation!.ids, ['bus_1utama']);
    expect(entry.destinationStation!.ids, ['rail_klcc']);
    expect(entry.routeSignature, 'DIR_250_KJ');
    expect(entry.transitSteps.single.name, '250 via Wangsa Maju');
    expect(entry.transitSteps.single.description, 'Board at Taman Bunga Raya');
  });

  testWidgets('tapping a travel history row opens journey details', (
    tester,
  ) async {
    final createdAt = DateTime(2026, 9, 7, 9, 37);
    final historyEntry = TravelHistoryEntry(
      origin: 'TAMAN BUNGA RAYA',
      destination: 'UTAR PINTU 2',
      fare: 5.25,
      currency: 'MYR',
      departureTime: '09:37',
      estimatedArrivalTime: '10:09',
      durationMinutes: 32,
      createdAt: createdAt,
      lineName: '250 via Wangsa Maju',
      transitSteps: const [
        TravelHistoryStep(
          mode: 'Bus',
          name: '250 via Wangsa Maju',
          duration: '27 min',
          description: 'Board at Taman Bunga Raya',
        ),
      ],
    );
    await launch(
      tester,
      PersonalTravelScreen(
        service: ProfileServiceStub(history: [historyEntry]),
        savedRoutesRepository: MemoryRoutes(),
      ),
    );

    await tester.tap(find.byKey(const Key('open-travel-history')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('history-trip-${createdAt.toIso8601String()}')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Trip Details'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    expect(find.text('32 min'), findsOneWidget);
    expect(find.text('RM 5.25'), findsWidgets);
    expect(find.text('250 via Wangsa Maju'), findsWidgets);
    expect(find.byKey(const Key('start-journey-again')), findsOneWidget);
  });

  testWidgets('travel history can replan and start the same journey again', (
    tester,
  ) async {
    final createdAt = DateTime(2026, 9, 7, 9, 37);
    final api = PlanningApi();
    final historyEntry = TravelHistoryEntry(
      origin: 'CURRENT ORIGIN',
      destination: 'CURRENT DESTINATION',
      fare: 2,
      currency: 'MYR',
      departureTime: '09:37',
      createdAt: createdAt,
      lineName: 'Kelana Jaya',
      originStation: station('CURRENT ORIGIN', ['rail_a']),
      destinationStation: station('CURRENT DESTINATION', ['rail_c']),
      routeSignature: 'DIR_rail_KJ',
      transitSteps: const [
        TravelHistoryStep(
          mode: 'Rail',
          name: 'Kelana Jaya',
          duration: '10 min',
          description: 'Board at CURRENT ORIGIN',
        ),
      ],
    );
    await launch(
      tester,
      PersonalTravelScreen(
        service: ProfileServiceStub(history: [historyEntry]),
        savedRoutesRepository: MemoryRoutes(),
        savedPlacesRepository: MemoryPlaces(),
        journeyApiService: api,
        journeyAuthenticate: (_) async => true,
      ),
    );

    await tester.tap(find.byKey(const Key('open-travel-history')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(Key('history-trip-${createdAt.toIso8601String()}')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('start-journey-again')));
    await tester.pumpAndSettle();

    final planning = tester.widget<JourneyPlanningScreen>(
      find.byType(JourneyPlanningScreen),
    );
    expect(planning.savedRoute!.origin.name, 'CURRENT ORIGIN');
    expect(planning.savedRoute!.destination.name, 'CURRENT DESTINATION');
    expect(planning.savedRoute!.stableServiceSequence, ['KELANA JAYA']);
    expect(api.searches, 1);
    expect(find.text('10 min'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legacy travel history replays by matching current station names',
    (tester) async {
      final createdAt = DateTime(2026, 9, 6, 8);
      final api = PlanningApi();
      await launch(
        tester,
        PersonalTravelScreen(
          service: ProfileServiceStub(
            history: [trip('CURRENT ORIGIN', 'CURRENT DESTINATION', createdAt)],
          ),
          savedRoutesRepository: MemoryRoutes(),
          savedPlacesRepository: MemoryPlaces(),
          journeyApiService: api,
          journeyAuthenticate: (_) async => true,
        ),
      );

      await tester.tap(find.byKey(const Key('open-travel-history')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(Key('history-trip-${createdAt.toIso8601String()}')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('start-journey-again')));
      await tester.pumpAndSettle();

      final planning = tester.widget<JourneyPlanningScreen>(
        find.byType(JourneyPlanningScreen),
      );
      expect(planning.savedRoute!.origin.name, 'CURRENT ORIGIN');
      expect(planning.savedRoute!.destination.name, 'CURRENT DESTINATION');
      expect(api.searches, 1);
      expect(tester.takeException(), isNull);
    },
  );

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
    'smart routine saves the successful history route without searching again',
    () async {
      final repository = MemoryRoutes();
      final api = PlanningApi()..results = [];
      final sourceTrip = TravelHistoryEntry(
        origin: '1 UTAMA',
        destination: 'KLCC',
        fare: 5.25,
        currency: 'MYR',
        departureTime: '09:37',
        createdAt: DateTime(2026, 9, 7),
        lineName: '250 via Wangsa Maju',
        originStation: station('1 UTAMA', ['bus_1utama']),
        destinationStation: station('KLCC', ['rail_klcc']),
        routeSignature: 'DIR_250_KJ',
      );
      final suggestion = RoutineSuggestion(
        origin: sourceTrip.origin,
        destination: sourceTrip.destination,
        tripCount: 3,
        commonWeekdays: const {1, 3, 5},
        mostRecentTrip: sourceTrip.createdAt,
        sourceTrip: sourceTrip,
      );
      final service = SmartRoutineService(repository, apiService: api);

      final saved = await service.findOrCreateFavourite(suggestion);

      expect(api.searches, 0);
      expect(saved.signature, startsWith('stable-route-v1:'));
      expect(saved.stableServiceSequence, ['250']);
      expect(saved.origin.ids, ['bus_1utama']);
      expect(saved.destination.ids, ['rail_klcc']);
      expect(repository.routes, hasLength(1));
    },
  );

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
      expect(payload['route_signature'], startsWith('stable-route-v1:'));
      expect(payload.containsKey('scheduledDepart'), false);
    },
  );

  test(
    'route identity uses direction and services but ignores dynamic signature',
    () {
      final original = sampleRoute();
      expect(
        sampleRoute(name: 'Renamed', ids: ['rail_a', 'rail_b']).routeKey,
        original.routeKey,
      );
      expect(sampleRoute(signature: 'OTHER').routeKey, original.routeKey);
      expect(
        sampleRoute(lineName: 'Kajang Line').routeKey,
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

  test('favourite identity ignores all time and trip-result fields', () {
    final firstJourney = {
      'sig': 'trip-a-at-0800',
      'name': '251 -> 250',
      'scheduledDepart': '08:00',
      'scheduledArrival': '08:45',
      'wait': 2,
      'duration': '45 min',
      'rank': 1,
      'tripId': 'weekday-trip-a',
      'legs': [
        {'mode': 'Bus', 'name': '251'},
        {'mode': 'Walk', 'name': 'Transfer'},
        {'mode': 'Bus', 'name': '250'},
      ],
    };
    final currentJourney = {
      'sig': 'trip-z-at-1730',
      'name': '251 → 250',
      'scheduledDepart': '17:30',
      'scheduledArrival': '18:40',
      'wait': 18,
      'duration': '70 min',
      'rank': 9,
      'tripId': 'updated-timetable-trip-z',
      'legs': [
        {'mode': 'Bus', 'name': '251'},
        {'mode': 'Walk', 'name': 'Transfer'},
        {'mode': 'Bus', 'name': '250'},
      ],
    };
    final favourite = sampleRoute(
      signature: SavedRoute.stableSignatureFromJourney(firstJourney),
      lineName: '251 → 250',
      serviceSequence: SavedRoute.servicesFromJourney(firstJourney),
      transportModes: SavedRoute.transportModesFromJourney(firstJourney),
    );

    expect(favourite.matchesJourney(currentJourney), isTrue);
    expect(
      SavedRoute.stableSignatureFromJourney(currentJourney),
      favourite.signature,
    );
    expect(
      favourite.matchesJourney({
        ...currentJourney,
        'name': '251 → 252',
        'legs': [
          {'mode': 'Bus', 'name': '251'},
          {'mode': 'Bus', 'name': '252'},
        ],
      }),
      isFalse,
    );

    final setapakFavourite = sampleRoute(
      signature: SavedRoute.stableSignatureFor(
        const ['251', '250'],
        const ['Bus', 'Bus'],
      ),
      lineName: '251 → 250',
      serviceSequence: const ['251', '250'],
      transportModes: const ['Bus', 'Bus'],
    );
    expect(
      setapakFavourite.matchesJourney({
        'sig': 'new-trip-and-transfer-data',
        'name': '251 -> 250 (via SRI PELANGI CONDO)',
        'legs': [
          {'mode': 'Bus', 'name': '251'},
          {'mode': 'Transfer', 'name': 'SRI PELANGI CONDO'},
          {'mode': 'Bus', 'name': '250'},
        ],
      }),
      isTrue,
    );
  });

  test(
    'resolves current GTFS IDs and does not guess a replacement station',
    () {
      final saved = sampleRoute();
      final current = station('New station label', ['rail_b', 'rail_new']);
      expect(saved.resolveOrigin([current])!.ids, [
        'rail_a',
        'rail_b',
        'rail_new',
      ]);
      expect(
        saved.resolveOrigin([
          station('KL SENTRAL', ['unrelated']),
        ]),
        isNull,
      );
    },
  );

  test('restores the intended station when nearby stations share an ID', () {
    final savedOrigin = StationModel(
      ids: const ['shared-stop', 'pv128-platform'],
      name: 'PV128 SETAPAK',
      lines: const {'251'},
      category: 'Bus',
      lat: 3.202,
      lon: 101.714,
    );
    final saved = SavedRoute(
      name: 'Home',
      origin: savedOrigin,
      destination: station('TAMAN BUNGA RAYA', ['destination']),
      signature: SavedRoute.stableSignatureFor(
        const ['251', '250'],
        const ['Bus', 'Bus'],
      ),
      lineName: '251 → 250',
      serviceSequence: const ['251', '250'],
    );
    final wrongNearbyStation = StationModel(
      ids: const ['shared-stop'],
      name: 'WANGSA MAJU',
      lines: const {'251'},
      category: 'Bus',
      lat: 3.198,
      lon: 101.710,
    );
    final intendedStation = StationModel(
      ids: const ['shared-stop', 'pv128-current'],
      name: 'PV128 SETAPAK',
      lines: const {'251'},
      category: 'Bus',
      lat: 3.2021,
      lon: 101.7141,
    );

    final restored = saved.resolveOrigin([wrongNearbyStation, intendedStation]);

    expect(restored, isNotNull);
    expect(restored!.name, 'PV128 SETAPAK');
    expect(restored.ids, ['pv128-current', 'pv128-platform', 'shared-stop']);
    expect(restored.lat, savedOrigin.lat);
    expect(restored.lon, savedOrigin.lon);
  });

  testWidgets(
    'reopening keeps the complete saved station IDs used by route search',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final origin = StationModel(
        ids: const ['pv128-main', 'pv128-t250-platform'],
        name: 'PV128 SETAPAK',
        lines: const {'T250'},
        category: 'Bus',
        lat: 3.202,
        lon: 101.714,
      );
      final destination = StationModel(
        ids: const ['pv16-main', 'pv16-t250-platform'],
        name: 'PV16',
        lines: const {'T250'},
        category: 'Bus',
        lat: 3.208,
        lon: 101.72,
      );
      final favourite = SavedRoute(
        id: 'setapak-pv16',
        name: 'PV128 to PV16',
        origin: origin,
        destination: destination,
        signature: SavedRoute.stableSignatureFor(const ['T250'], const ['Bus']),
        lineName: 'T250',
        serviceSequence: const ['T250'],
        transportModes: const ['Bus'],
      );
      final api = PlanningApi()
        ..stations = [
          StationModel(
            ids: const ['pv128-main'],
            name: 'PV128 SETAPAK',
            lines: const {'T250'},
            category: 'Bus',
            lat: 3.202,
            lon: 101.714,
          ),
          StationModel(
            ids: const ['pv16-main'],
            name: 'PV16',
            lines: const {'T250'},
            category: 'Bus',
            lat: 3.208,
            lon: 101.72,
          ),
        ]
        ..requiredOriginId = 'pv128-t250-platform'
        ..requiredDestinationId = 'pv16-t250-platform'
        ..results = [
          {
            'sig': 'current-t250-trip',
            'name': 'T250',
            'duration': '7 min',
            'fare': 'RM 1.00',
            'scheduledDepart': '17:36',
            'legs': [
              {'mode': 'Bus', 'name': 'T250'},
            ],
          },
        ];

      await tester.pumpWidget(
        MaterialApp(
          home: JourneyPlanningScreen(
            savedRoute: favourite,
            apiService: api,
            savedRoutesRepository: MemoryRoutes(),
            authenticate: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.requestedOrigin!.ids, contains('pv128-t250-platform'));
      expect(api.requestedDestination!.ids, contains('pv16-t250-platform'));
      expect(find.text('PV128 to PV16'), findsOneWidget);
      expect(find.byKey(const Key('refresh-saved-route')), findsOneWidget);
      expect(find.text('JOURNEY SUMMARY'), findsOneWidget);
      expect(find.text('ROUTE OPTIMIZATION'), findsNothing);
      expect(find.text('ROAD SEARCH'), findsNothing);
      expect(find.text('ROUTE COMPARISON'), findsNothing);
      expect(find.text('T250'), findsWidgets);
      expect(find.text('7 min'), findsOneWidget);
      expect(
        find.text('No routes found. Try another origin or destination.'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
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

  testWidgets('compact favourite card displays and renames the route name', (
    tester,
  ) async {
    final repository = MemoryRoutes()..routes = [sampleRoute()];
    await launch(
      tester,
      FavouriteRoutesScreen(repository: repository, sheetMode: true),
    );

    expect(
      find.byKey(const Key('favourite-route-name-saved-1')),
      findsOneWidget,
    );
    expect(find.text('Work'), findsOneWidget);

    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Campus Run');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Campus Run'), findsOneWidget);
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

  testWidgets('View live route returns the selected favourite', (tester) async {
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
    await tester.tap(find.text('View live route'));
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
      expect(api.requestedOrigin!.ids, ['rail_a', 'rail_b']);
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
      expect(
        repository.routes.single.signature,
        startsWith('stable-route-v1:'),
      );
      expect(repository.routes.single.stableServiceSequence, ['KELANA JAYA']);
      expect(repository.routes.single.stableTransportModes, ['RAIL']);
      expect(find.text('Saved'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'replanning matches the same line sequence when its signature changed',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = PlanningApi()
        ..results = [
          {
            'sig': 'OTHER',
            'name': 'T250 -> 251 (via Wangsa Maju)',
            'duration': '10 min',
            'fare': 'RM 2.00',
            'scheduledDepart': '12:00',
            'legs': [
              {'mode': 'Bus', 'name': 'T250'},
              {'mode': 'Bus', 'name': '251'},
            ],
          },
          {
            'sig': 'CURRENT_SIGNATURE',
            'name': 'T250 -> 250 (via Wangsa Maju)',
            'duration': '30 min',
            'fare': 'RM 3.00',
            'scheduledDepart': '13:00',
            'legs': [
              {'mode': 'Bus', 'name': 'T250'},
              {'mode': 'Bus', 'name': '250'},
            ],
          },
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: JourneyPlanningScreen(
            savedRoute: sampleRoute(
              signature: 'STALE_SIGNATURE',
              lineName: 'T250 → 250 (via Old Wangsa Maju)',
            ),
            apiService: api,
            savedRoutesRepository: MemoryRoutes(),
            authenticate: (_) async => true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('30 min'), findsOneWidget);
      expect(
        find.text(
          'Your saved route is unavailable. Showing other routes for these locations.',
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('replanning restores the saved three-service Wangsa Maju route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PlanningApi()
      ..results = [
        {
          'sig': '2X_T222_OTHER_LINE_5_OTHER_303',
          'name': 'T222 -> Line 5 (Kelana Jaya) -> 303',
          'duration': '40 min',
          'fare': 'RM 4.48',
          'scheduledDepart': '12:00',
          'legs': [
            {'mode': 'Bus', 'name': 'T222'},
            {'mode': 'Walk', 'name': 'Transfer'},
            {'mode': 'Rail', 'name': 'Line 5 (Kelana Jaya)'},
            {'mode': 'Walk', 'name': 'Transfer'},
            {'mode': 'Bus', 'name': '303'},
          ],
        },
        {
          'sig': 'ALTERNATIVE_2',
          'name': 'T222 -> Line 5 (Kelana Jaya) -> 302',
          'duration': '41 min',
          'fare': 'RM 4.48',
          'scheduledDepart': '12:10',
          'legs': [
            {'mode': 'Bus', 'name': 'T222'},
            {'mode': 'Rail', 'name': 'Line 5 (Kelana Jaya)'},
            {'mode': 'Bus', 'name': '302'},
          ],
        },
        {
          'sig': 'ALTERNATIVE_3',
          'name': 'T222 -> Line 5 (Kelana Jaya) -> 304',
          'duration': '42 min',
          'fare': 'RM 4.48',
          'scheduledDepart': '12:20',
          'legs': [
            {'mode': 'Bus', 'name': 'T222'},
            {'mode': 'Rail', 'name': 'Line 5 (Kelana Jaya)'},
            {'mode': 'Bus', 'name': '304'},
          ],
        },
        {
          'sig': 'ALTERNATIVE_4',
          'name': 'T222 -> Line 5 (Kelana Jaya) -> 305',
          'duration': '43 min',
          'fare': 'RM 4.48',
          'scheduledDepart': '12:30',
          'legs': [
            {'mode': 'Bus', 'name': 'T222'},
            {'mode': 'Rail', 'name': 'Line 5 (Kelana Jaya)'},
            {'mode': 'Bus', 'name': '305'},
          ],
        },
        {
          'sig': '2X_T222_NEW_STATION_LINE_5_NEW_STOP_300',
          'name': 'T222 -> Line 5 (Kelana Jaya) -> 300',
          'duration': '44 min',
          'fare': 'RM 4.48',
          'scheduledDepart': '13:00',
          'legs': [
            {'mode': 'Bus', 'name': 'T222'},
            // Internal planner metadata may represent an interchange as its
            // own leg even though the visible service sequence is unchanged.
            {'mode': 'Transfer', 'name': 'Interchange'},
            {'mode': 'Rail', 'name': 'Line 5 (Kelana Jaya)'},
            {'mode': 'Walk', 'name': 'Transfer'},
            {'mode': 'Bus', 'name': '300'},
          ],
        },
      ];
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPlanningScreen(
          savedRoute: sampleRoute(
            signature: SavedRoute.stableSignatureFor(
              const ['T222', 'Line 5 (Kelana Jaya)', '300'],
              const ['Bus', 'Rail', 'Bus'],
            ),
            lineName: 'T222 → Line 5 (Kelana Jaya) → 300',
            serviceSequence: const ['T222', 'Line 5 (Kelana Jaya)', '300'],
            transportModes: const ['Bus', 'Transfer', 'Rail', 'Bus'],
          ),
          apiService: api,
          savedRoutesRepository: MemoryRoutes(),
          authenticate: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Refresh live status'), findsOneWidget);
    expect(find.text('44 min'), findsOneWidget);
    expect(
      find.text(
        'Your saved route is unavailable. Showing other routes for these locations.',
      ),
      findsNothing,
    );
    await tester.tap(find.text('Refresh live status'));
    await tester.pumpAndSettle();
    expect(api.searches, 2);
    expect(
      find.text(
        'Your saved route is unavailable. Showing other routes for these locations.',
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Journey Planning returns a route for Daily Commute', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = PlanningApi();
    SavedRoute? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                selected = await Navigator.push<SavedRoute>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => JourneyPlanningScreen(
                      savedRoute: sampleRoute(),
                      selectForDailyCommute: true,
                      apiService: api,
                      savedRoutesRepository: MemoryRoutes(),
                      authenticate: (_) async => true,
                    ),
                  ),
                );
              },
              child: const Text('Choose route'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Choose route'));
    await tester.pumpAndSettle();
    expect(find.text('Choose commute route'), findsOneWidget);
    await tester.ensureVisible(find.text('Use for Daily Commute'));
    await tester.tap(find.text('Use for Daily Commute'));
    await tester.pumpAndSettle();

    expect(selected, isNotNull);
    expect(selected!.id, isNull);
    expect(selected!.signature, startsWith('stable-route-v1:'));
    expect(selected!.stableServiceSequence, ['KELANA JAYA']);
    expect(selected!.origin.name, 'KL SENTRAL');
    expect(selected!.destination.name, 'KLCC');
    expect(tester.takeException(), isNull);
  });

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

  testWidgets('a previously saved route shows the Saved summary action', (
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

    final savedAction = find.byKey(const Key('toggle-saved-route'));
    expect(savedAction, findsOneWidget);
    expect(
      find.descendant(of: savedAction, matching: find.byIcon(Icons.favorite)),
      findsOneWidget,
    );
    expect(find.text('Saved'), findsOneWidget);
  });

  testWidgets('the Saved summary button removes the favourite route', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryRoutes()..routes = [sampleRoute()];
    await tester.pumpWidget(
      MaterialApp(
        home: JourneyPlanningScreen(
          savedRoute: sampleRoute(),
          apiService: PlanningApi(),
          savedRoutesRepository: repository,
          authenticate: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.byKey(const Key('toggle-saved-route'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(repository.routes, isEmpty);
    expect(find.text('Save route'), findsOneWidget);
    expect(find.text('Route removed from Favourite Routes.'), findsOneWidget);
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
