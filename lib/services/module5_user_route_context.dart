import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';
import 'personal_travel_service.dart';

const module5ActiveJourneyScope = '__active_journey__';
const module5RoutineRoutesScope = '__routine_routes__';
const module5MyRoutesScope = '__my_routes__';
const module5AllNetworkScope = '__all_network__';

String module5PreferredScope({
  required Set<String> activeRoutes,
  required Set<String> routineRoutes,
  required Set<String> myRoutes,
}) {
  if (activeRoutes.isNotEmpty) return module5ActiveJourneyScope;
  if (routineRoutes.isNotEmpty) return module5RoutineRoutesScope;
  if (myRoutes.isNotEmpty) return module5MyRoutesScope;
  return module5AllNetworkScope;
}

Set<String> module5BusRoutesFromJourneySteps(Iterable<dynamic> steps) => {
  for (final step in steps)
    if (step is Map &&
        step['mode']?.toString().trim().toLowerCase() == 'bus' &&
        _normaliseRoute(step['name']?.toString() ?? '').isNotEmpty)
      _normaliseRoute(step['name']?.toString() ?? ''),
};

typedef SavedRoutesLoader = Future<List<SavedRoute>> Function();
typedef DailyCommutesLoader = Future<List<DailyCommute>> Function();

abstract interface class Module5RouteStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<void> remove(String key);
}

class SharedPreferencesModule5RouteStore implements Module5RouteStore {
  SharedPreferencesModule5RouteStore({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  final SharedPreferencesAsync _preferences;

  @override
  Future<String?> getString(String key) => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}

@immutable
class Module5ActiveJourney {
  const Module5ActiveJourney({
    required this.busRoutes,
    required this.origin,
    required this.destination,
    required this.startedAt,
    required this.expiresAt,
  });

  factory Module5ActiveJourney.fromJson(Map<String, dynamic> json) {
    final routes = json['bus_routes'];
    return Module5ActiveJourney(
      busRoutes: routes is List
          ? {
              for (final route in routes)
                if (_normaliseRoute('$route').isNotEmpty)
                  _normaliseRoute('$route'),
            }
          : const {},
      origin: json['origin']?.toString().trim() ?? '',
      destination: json['destination']?.toString().trim() ?? '',
      startedAt:
          DateTime.tryParse(json['started_at']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt:
          DateTime.tryParse(json['expires_at']?.toString() ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final Set<String> busRoutes;
  final String origin;
  final String destination;
  final DateTime startedAt;
  final DateTime expiresAt;

  bool isExpiredAt(DateTime instant) =>
      !expiresAt.isAfter(instant.toUtc()) || busRoutes.isEmpty;

  Map<String, dynamic> toJson() => {
    'bus_routes': busRoutes.toList()..sort(),
    'origin': origin,
    'destination': destination,
    'started_at': startedAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}


class Module5UserRouteContext extends ChangeNotifier {
  Module5UserRouteContext({
    Module5RouteStore? store,
    this.savedRoutesLoader,
    this.dailyCommutesLoader,
  }) : _providedStore = store;

  static final Module5UserRouteContext shared = Module5UserRouteContext();
  static const _activeJourneyKey = 'module5.active_journey';

  final Module5RouteStore? _providedStore;
  final SavedRoutesLoader? savedRoutesLoader;
  final DailyCommutesLoader? dailyCommutesLoader;
  Module5RouteStore? _fallbackStore;

  Module5RouteStore get _store =>
      _providedStore ??
      (_fallbackStore ??= SharedPreferencesModule5RouteStore());

  Module5ActiveJourney? _activeJourney;
  Set<String> _dailyCommuteRoutes = const {};
  Set<String> _favouriteRoutes = const {};
  bool _localLoaded = false;
  bool _personalRoutesLoading = false;
  Object? _personalRoutesError;
  DateTime? _personalRoutesUpdatedAt;
  Future<void>? _loadRequest;
  int _activeMutation = 0;
  bool _disposed = false;

  Module5ActiveJourney? get activeJourney {
    final journey = _activeJourney;
    if (journey != null && journey.isExpiredAt(DateTime.now())) return null;
    return journey;
  }

  Set<String> get activeRoutes =>
      Set.unmodifiable(activeJourney?.busRoutes ?? const <String>{});
  Set<String> get dailyCommuteRoutes => Set.unmodifiable(_dailyCommuteRoutes);
  Set<String> get favouriteRoutes => Set.unmodifiable(_favouriteRoutes);
  Set<String> get routineRoutes =>
      Set.unmodifiable({..._dailyCommuteRoutes, ..._favouriteRoutes});
  bool get localLoaded => _localLoaded;
  bool get personalRoutesLoading => _personalRoutesLoading;
  Object? get personalRoutesError => _personalRoutesError;

  Future<void> load({bool forcePersonalRoutes = false}) {
    final existing = _loadRequest;
    if (existing != null) return existing;
    final request = _performLoad(forcePersonalRoutes: forcePersonalRoutes);
    _loadRequest = request;
    return request.whenComplete(() {
      if (identical(_loadRequest, request)) _loadRequest = null;
    });
  }

  Future<void> _performLoad({required bool forcePersonalRoutes}) async {
    await _loadActiveJourney();
    await refreshPersonalRoutes(force: forcePersonalRoutes);
  }

  Future<void> startJourney({
    required Iterable<String> busRoutes,
    required String origin,
    required String destination,
    required DateTime expiresAt,
    DateTime? startedAt,
  }) async {
    final routes = {
      for (final route in busRoutes)
        if (_normaliseRoute(route).isNotEmpty) _normaliseRoute(route),
    };
    if (routes.isEmpty) {
      await endJourney();
      return;
    }
    final now = (startedAt ?? DateTime.now()).toUtc();
    final safeExpiry = expiresAt.toUtc().isAfter(now)
        ? expiresAt.toUtc()
        : now.add(const Duration(hours: 1));
    final journey = Module5ActiveJourney(
      busRoutes: Set.unmodifiable(routes),
      origin: origin.trim(),
      destination: destination.trim(),
      startedAt: now,
      expiresAt: safeExpiry,
    );
    _activeMutation++;
    _activeJourney = journey;
    _localLoaded = true;
    _notifyListeners();
    try {
      await _store.setString(_activeJourneyKey, jsonEncode(journey.toJson()));
    } on Object catch (error) {
      debugPrint('Unable to persist Module 5 active journey: $error');
    }
  }

  Future<void> endJourney() async {
    final hadJourney = _activeJourney != null;
    _activeMutation++;
    _activeJourney = null;
    _localLoaded = true;
    if (hadJourney) _notifyListeners();
    try {
      await _store.remove(_activeJourneyKey);
    } on Object catch (error) {
      debugPrint('Unable to clear Module 5 active journey: $error');
    }
  }

  Future<void> _loadActiveJourney() async {
    final mutation = _activeMutation;
    try {
      final encoded = await _store.getString(_activeJourneyKey);
      if (mutation != _activeMutation) return;
      if (encoded == null || encoded.isEmpty) {
        _activeJourney = null;
      } else {
        final decoded = jsonDecode(encoded);
        final journey = decoded is Map
            ? Module5ActiveJourney.fromJson(Map<String, dynamic>.from(decoded))
            : null;
        _activeJourney = journey == null || journey.isExpiredAt(DateTime.now())
            ? null
            : journey;
        if (_activeJourney == null) {
          await _store.remove(_activeJourneyKey);
        }
      }
    } on Object catch (error) {
      _activeJourney = null;
      debugPrint('Unable to load Module 5 active journey: $error');
    } finally {
      if (mutation == _activeMutation) {
        _localLoaded = true;
        _notifyListeners();
      }
    }
  }

  Future<void> refreshPersonalRoutes({bool force = false}) async {
    if (_personalRoutesLoading) return;
    final updatedAt = _personalRoutesUpdatedAt;
    if (!force &&
        updatedAt != null &&
        DateTime.now().difference(updatedAt) < const Duration(minutes: 5)) {
      return;
    }
    _personalRoutesLoading = true;
    _personalRoutesError = null;
    _notifyListeners();

    try {
      SavedRoutesLoader? savedLoader = savedRoutesLoader;
      DailyCommutesLoader? commuteLoader = dailyCommutesLoader;
      if (savedLoader == null || commuteLoader == null) {
        SupabaseClient client;
        try {
          client = Supabase.instance.client;
        } on Object {
          _dailyCommuteRoutes = const {};
          _favouriteRoutes = const {};
          return;
        }
        if (client.auth.currentUser == null) {
          _dailyCommuteRoutes = const {};
          _favouriteRoutes = const {};
          return;
        }
        savedLoader ??= SupabaseSavedRoutesRepository(client: client).load;
        commuteLoader ??= SupabaseDailyCommuteRepository(
          client: client,
        ).loadAll;
      }

      final results = await Future.wait<Object>([
        savedLoader(),
        commuteLoader(),
      ]);
      final savedRoutes = results[0] as List<SavedRoute>;
      final commutes = results[1] as List<DailyCommute>;
      final savedById = {
        for (final route in savedRoutes)
          if (route.id != null) route.id!: route,
      };
      _favouriteRoutes = Set.unmodifiable(_routeCodes(savedRoutes));
      _dailyCommuteRoutes = Set.unmodifiable(
        _routeCodes(
          commutes
              .map((commute) => savedById[commute.savedRouteId])
              .whereType<SavedRoute>(),
        ),
      );
      _personalRoutesUpdatedAt = DateTime.now();
    } on Object catch (error) {

      _personalRoutesError = error;
      _dailyCommuteRoutes = const {};
      _favouriteRoutes = const {};
      debugPrint('Unable to load Module 5 personal routes: $error');
    } finally {
      _personalRoutesLoading = false;
      _notifyListeners();
    }
  }

  void _notifyListeners() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  static Set<String> _routeCodes(Iterable<SavedRoute> routes) => {
    for (final route in routes)
      for (final identifier in _routeIdentifiers(route)) identifier,
  };


  static Iterable<String> _routeIdentifiers(SavedRoute route) sync* {
    final lineName = _normaliseRoute(route.lineName);
    if (lineName.isNotEmpty) yield lineName;

    final signature = _normaliseRoute(route.signature);
    for (final value in [lineName, signature]) {
      for (final match in RegExp(r'[A-Z]*\d+[A-Z0-9]*').allMatches(value)) {
        final token = match.group(0);
        if (token != null && token.isNotEmpty) yield token;
      }
    }
  }
}

String _normaliseRoute(String value) => value.trim().toUpperCase();
