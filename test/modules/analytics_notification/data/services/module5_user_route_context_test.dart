import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nextroute_assignment/services/api_service.dart';
import 'package:nextroute_assignment/services/module5_user_route_context.dart';
import 'package:nextroute_assignment/services/notification_service.dart';
import 'package:nextroute_assignment/services/personal_travel_service.dart';

void main() {
  test('only bus legs become active route codes', () {
    expect(
      module5BusRoutesFromJourneySteps(const [
        {'mode': 'Walk', 'name': ''},
        {'mode': 'Rail', 'name': 'KJ'},
        {'mode': 'Bus', 'name': ' t250 '},
        {'mode': 'bus', 'name': '250'},
      ]),
      {'T250', '250'},
    );
  });

  test('route scope follows active, routine, my routes, then network', () {
    expect(
      module5PreferredScope(
        activeRoutes: const {'T250'},
        routineRoutes: const {'250'},
        myRoutes: const {'T105'},
      ),
      module5ActiveJourneyScope,
    );
    expect(
      module5PreferredScope(
        activeRoutes: const {},
        routineRoutes: const {'250'},
        myRoutes: const {'T105'},
      ),
      module5RoutineRoutesScope,
    );
    expect(
      module5PreferredScope(
        activeRoutes: const {},
        routineRoutes: const {},
        myRoutes: const {'T105'},
      ),
      module5MyRoutesScope,
    );
    expect(
      module5PreferredScope(
        activeRoutes: const {},
        routineRoutes: const {},
        myRoutes: const {},
      ),
      module5AllNetworkScope,
    );
  });

  test('active bus routes are normalized, persisted and restored', () async {
    final store = _MemoryRouteStore();
    final first = _context(store);
    addTearDown(first.dispose);
    final now = DateTime.now().toUtc();

    await first.startJourney(
      busRoutes: const [' t250 ', '250', '', 'T250'],
      origin: 'Wangsa Maju',
      destination: 'Setapak Central',
      startedAt: now,
      expiresAt: now.add(const Duration(hours: 2)),
    );

    expect(first.activeRoutes, {'T250', '250'});
    expect(first.activeJourney?.origin, 'Wangsa Maju');

    final restored = _context(store);
    addTearDown(restored.dispose);
    await restored.load();

    expect(restored.activeRoutes, {'T250', '250'});
    expect(restored.activeJourney?.destination, 'Setapak Central');
  });

  test('a newly started journey wins over an older load request', () async {
    final store = _DelayedRouteStore();
    final context = Module5UserRouteContext(
      store: store,
      savedRoutesLoader: () async => const [],
      dailyCommutesLoader: () async => const [],
    );
    addTearDown(context.dispose);

    final loading = context.load();
    await context.startJourney(
      busRoutes: const ['T250'],
      origin: 'A',
      destination: 'B',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );
    store.release(null);
    await loading;

    expect(context.activeRoutes, {'T250'});
  });

  test('expired active journey is not restored', () async {
    final store = _MemoryRouteStore();
    await store.setString(
      'module5.active_journey',
      jsonEncode({
        'bus_routes': ['T250'],
        'origin': 'A',
        'destination': 'B',
        'started_at': '2020-01-01T00:00:00Z',
        'expires_at': '2020-01-01T01:00:00Z',
      }),
    );
    final context = _context(store);
    addTearDown(context.dispose);

    await context.load();

    expect(context.activeJourney, isNull);
    expect(context.activeRoutes, isEmpty);
  });

  test(
    'daily commute and favourite routes are read without mutation',
    () async {
      final t250 = _savedRoute(id: 'route-1', lineName: 'T250');
      final route250 = _savedRoute(id: 'route-2', lineName: '250');
      final context = Module5UserRouteContext(
        store: _MemoryRouteStore(),
        savedRoutesLoader: () async => [t250, route250],
        dailyCommutesLoader: () async => [
          DailyCommute(
            id: 'commute-1',
            userId: 'user-1',
            savedRouteId: 'route-2',
            origin: 'A',
            destination: 'B',
            departureTimeMinutes: 9 * 60,
            activeDays: const {1, 2, 3, 4, 5},
            reminderEnabled: true,
            reminderMinutesBefore: 10,
            estimatedDurationMinutes: 20,
          ),
        ],
      );
      addTearDown(context.dispose);

      await context.load();

      expect(context.favouriteRoutes, {'T250', '250'});
      expect(context.dailyCommuteRoutes, {'250'});
      expect(context.routineRoutes, {'T250', '250'});
      expect(context.personalRoutesError, isNull);
    },
  );

  test('personal route failure leaves device-local scopes usable', () async {
    final context = Module5UserRouteContext(
      store: _MemoryRouteStore(),
      savedRoutesLoader: () async => throw StateError('offline'),
      dailyCommutesLoader: () async => const [],
    );
    addTearDown(context.dispose);

    await context.load();

    expect(context.routineRoutes, isEmpty);
    expect(context.personalRoutesError, isA<StateError>());
  });

  test('forced load immediately refreshes newly saved favourite routes', () async {
    var loadCount = 0;
    final context = Module5UserRouteContext(
      store: _MemoryRouteStore(),
      savedRoutesLoader: () async {
        loadCount++;
        return loadCount == 1
            ? const []
            : [_savedRoute(id: 'route-1', lineName: 'T250')];
      },
      dailyCommutesLoader: () async => const [],
    );
    addTearDown(context.dispose);

    await context.load();
    expect(context.routineRoutes, isEmpty);

    await context.load(forcePersonalRoutes: true);

    expect(context.favouriteRoutes, {'T250'});
    expect(loadCount, 2);
  });

  test('older generic favourite recovers route ID from signature', () async {
    final context = Module5UserRouteContext(
      store: _MemoryRouteStore(),
      savedRoutesLoader: () async => [
        _savedRoute(
          id: 'route-1',
          lineName: 'Rapid Bus',
          signature: 'DIR_bus_U1510',
        ),
      ],
      dailyCommutesLoader: () async => const [],
    );
    addTearDown(context.dispose);

    await context.load();

    expect(context.favouriteRoutes, contains('U1510'));
  });
}

Module5UserRouteContext _context(_MemoryRouteStore store) =>
    Module5UserRouteContext(
      store: store,
      savedRoutesLoader: () async => const [],
      dailyCommutesLoader: () async => const [],
    );

class _MemoryRouteStore implements Module5RouteStore {
  final Map<String, String> values = {};

  @override
  Future<String?> getString(String key) async => values[key];

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }
}

class _DelayedRouteStore extends _MemoryRouteStore {
  final Completer<String?> _read = Completer<String?>();

  void release(String? value) => _read.complete(value);

  @override
  Future<String?> getString(String key) => _read.future;
}

SavedRoute _savedRoute({
  required String id,
  required String lineName,
  String? signature,
}) {
  final origin = StationModel(
    ids: const ['A'],
    name: 'A',
    lines: const {'Bus'},
    category: 'Bus',
    lat: 3.1,
    lon: 101.7,
  );
  final destination = StationModel(
    ids: const ['B'],
    name: 'B',
    lines: const {'Bus'},
    category: 'Bus',
    lat: 3.2,
    lon: 101.8,
  );
  return SavedRoute(
    id: id,
    name: lineName,
    origin: origin,
    destination: destination,
    signature: signature ?? 'DIR_bus_$lineName',
    lineName: lineName,
  );
}
