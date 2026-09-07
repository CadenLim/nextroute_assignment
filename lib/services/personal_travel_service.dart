import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'api_service.dart';
import 'personal_assistance_functions.dart';

class SavedRoute {
  const SavedRoute({
    this.id,
    required this.name,
    required this.origin,
    required this.destination,
    required this.signature,
    required this.lineName,
  });

  final String? id;
  final String name;
  final StationModel origin;
  final StationModel destination;
  final String signature;
  final String lineName;

  String get routeKey =>
      jsonEncode([_stationKey(origin), _stationKey(destination), signature]);

  static String _stationKey(StationModel station) {
    final ids = station.ids.toList()..sort();
    if (ids.isEmpty) throw const FormatException('Station has no GTFS ID.');
    return ids.first;
  }

  Map<String, dynamic> toInsert(String userId) => {
    'user_id': userId,
    'name': name.trim(),
    'route_key': routeKey,
    'origin': _stationJson(origin),
    'destination': _stationJson(destination),
    'route_signature': signature,
    'line_name': lineName,
  };

  factory SavedRoute.fromJson(Map<String, dynamic> json) => SavedRoute(
    id: json['id'] as String,
    name: json['name'] as String,
    origin: _stationFromJson(Map<String, dynamic>.from(json['origin'] as Map)),
    destination: _stationFromJson(
      Map<String, dynamic>.from(json['destination'] as Map),
    ),
    signature: json['route_signature'] as String,
    lineName: json['line_name'] as String,
  );

  static Map<String, dynamic> _stationJson(StationModel station) => {
    'ids': station.ids.toList()..sort(),
    'name': station.name,
    'lines': station.lines.toList()..sort(),
    'category': station.category,
    'lat': station.lat,
    'lon': station.lon,
  };

  static StationModel _stationFromJson(Map<String, dynamic> json) =>
      StationModel(
        ids: List<String>.from(json['ids'] as List),
        name: json['name'] as String,
        lines: Set<String>.from(json['lines'] as List),
        category: json['category'] as String,
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
      );

  StationModel? resolveOrigin(List<StationModel> stations) =>
      _resolve(origin, stations);

  StationModel? resolveDestination(List<StationModel> stations) =>
      _resolve(destination, stations);

  static StationModel? _resolve(
    StationModel saved,
    List<StationModel> stations,
  ) {
    for (final station in stations) {
      if (station.ids.any(saved.ids.contains)) {
        return StationModel(
          ids: station.ids,
          name: saved.name,
          lines: station.lines,
          category: station.category,
          lat: station.lat,
          lon: station.lon,
        );
      }
    }
    return null;
  }
}

enum SavedPlaceType {
  home('home', 'Home'),
  university('university', 'University'),
  work('work', 'Work');

  const SavedPlaceType(this.databaseValue, this.label);

  final String databaseValue;
  final String label;

  static SavedPlaceType fromDatabase(String value) => values.firstWhere(
    (type) => type.databaseValue == value,
    orElse: () => throw FormatException('Unknown saved place type: $value'),
  );
}

class SavedPlace {
  const SavedPlace({required this.type, required this.station, this.updatedAt});

  factory SavedPlace.fromJson(Map<String, dynamic> json) {
    final primaryId = json['station_id']?.toString() ?? '';
    final storedIds = json['station_ids'];
    final ids = storedIds is List
        ? List<String>.from(storedIds)
        : <String>[primaryId];
    return SavedPlace(
      type: SavedPlaceType.fromDatabase(json['place_type'].toString()),
      station: StationModel(
        ids: ids.where((id) => id.isNotEmpty).toList(),
        name: json['station_name']?.toString() ?? 'Unknown',
        lines: Set<String>.from(json['lines'] as List? ?? const []),
        category: json['category']?.toString() ?? 'Transit',
        lat: (json['latitude'] as num?)?.toDouble() ?? 0,
        lon: (json['longitude'] as num?)?.toDouble() ?? 0,
      ),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }

  final SavedPlaceType type;
  final StationModel station;
  final DateTime? updatedAt;

  Map<String, dynamic> toUpsert(String userId) {
    final ids = station.ids.toList()..sort();
    if (ids.isEmpty) throw const FormatException('Station has no GTFS ID.');
    return {
      'user_id': userId,
      'place_type': type.databaseValue,
      'station_id': ids.first,
      'station_ids': ids,
      'station_name': station.name,
      'lines': station.lines.toList()..sort(),
      'category': station.category,
      'latitude': station.lat,
      'longitude': station.lon,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  StationModel resolveStation(List<StationModel> currentStations) {
    for (final current in currentStations) {
      if (current.ids.any(station.ids.contains)) return current;
    }
    return station;
  }
}

abstract interface class SavedPlacesRepository {
  Future<List<SavedPlace>> load();
  Future<SavedPlace> upsert(SavedPlace place);
  Future<void> delete(SavedPlaceType type);
}

class SupabaseSavedPlacesRepository implements SavedPlacesRepository {
  SupabaseSavedPlacesRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client,
      _functions = PersonalAssistanceFunctions(client: client);

  final SupabaseClient _client;
  final PersonalAssistanceFunctions _functions;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  @override
  Future<List<SavedPlace>> load() async {
    final rows = await _functions.list('personal-data', 'list-saved-places');
    return rows.map(SavedPlace.fromJson).toList();
  }

  @override
  Future<SavedPlace> upsert(SavedPlace place) async {
    final placeData = place.toUpsert(_userId)..remove('user_id');
    final response = await _functions.invoke(
      'personal-data',
      'upsert-saved-place',
      payload: {'place': placeData},
    );
    final row = Map<String, dynamic>.from(response['data'] as Map);
    return SavedPlace.fromJson(row);
  }

  @override
  Future<void> delete(SavedPlaceType type) async {
    await _functions.invoke(
      'personal-data',
      'delete-saved-place',
      payload: {'place_type': type.databaseValue},
    );
  }
}

abstract class SavedRoutesRepository {
  Future<List<SavedRoute>> load();
  Future<int> count();
  Future<void> save(SavedRoute route);
  Future<void> rename(String id, String name);
  Future<void> delete(String id);
}

class SupabaseSavedRoutesRepository implements SavedRoutesRepository {
  SupabaseSavedRoutesRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client,
      _functions = PersonalAssistanceFunctions(client: client);

  final SupabaseClient _client;
  final PersonalAssistanceFunctions _functions;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  @override
  Future<List<SavedRoute>> load() async {
    final rows = await _functions.list('personal-data', 'list-saved-routes');
    return rows.map(SavedRoute.fromJson).toList();
  }

  @override
  Future<int> count() async {
    final response = await _functions.invoke(
      'personal-data',
      'count-saved-routes',
    );
    return (response['count'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> save(SavedRoute route) async {
    _validateName(route.name);
    final routeData = route.toInsert(_userId)..remove('user_id');
    await _functions.invoke(
      'personal-data',
      'upsert-saved-route',
      payload: {'route': routeData},
    );
  }

  @override
  Future<void> rename(String id, String name) async {
    _validateName(name);
    await _functions.invoke(
      'personal-data',
      'rename-saved-route',
      payload: {'id': id, 'name': name.trim()},
    );
  }

  @override
  Future<void> delete(String id) async {
    await _functions.invoke(
      'personal-data',
      'delete-saved-route',
      payload: {'id': id},
    );
  }

  void _validateName(String name) {
    if (name.trim().isEmpty || name.trim().length > 80) {
      throw ArgumentError('Route name must contain 1 to 80 characters.');
    }
  }
}

class PasswordCodeLogin {
  PasswordCodeLogin({
    required this.auth,
    String? projectUrl,
    String? publishableKey,
    http.Client Function()? passwordClientFactory,
    LoginAttemptGuard? loginAttemptGuard,
  }) : _projectUrl = projectUrl ?? SupabaseConfig.url,
       _publishableKey = publishableKey ?? SupabaseConfig.publishableKey,
       _passwordClientFactory = passwordClientFactory ?? http.Client.new,
       _loginAttemptGuard = loginAttemptGuard ?? SupabaseLoginAttemptGuard();

  final GoTrueClient auth;
  final String _projectUrl;
  final String _publishableKey;
  final http.Client Function() _passwordClientFactory;
  final LoginAttemptGuard _loginAttemptGuard;

  Future<void> sendCode({
    required String email,
    required String password,
  }) async {
    await _loginAttemptGuard.verifyLogin(email: email, password: password);
    await auth.signInWithOtp(email: email, shouldCreateUser: false);
  }

  Future<void> verifyPassword({
    required String email,
    required String password,
  }) async {
    final client = _passwordClientFactory();
    try {
      final response = await client
          .post(
            Uri.parse('$_projectUrl/auth/v1/token?grant_type=password'),
            headers: {
              'apikey': _publishableKey,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        throw AuthException(
          (body['msg'] ??
                  body['error_description'] ??
                  body['message'] ??
                  'Unable to verify your password. Please try again.')
              .toString(),
        );
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final token = body['access_token'];
      if (token is! String || token.isEmpty) {
        throw const AuthException(
          'Unable to verify your password. Please try again.',
        );
      }
      final logout = await client
          .post(
            Uri.parse('$_projectUrl/auth/v1/logout?scope=local'),
            headers: {
              'apikey': _publishableKey,
              'Authorization': 'Bearer $token',
            },
          )
          .timeout(const Duration(seconds: 30));
      if (logout.statusCode < 200 || logout.statusCode >= 300) {
        throw const AuthException(
          'Unable to complete password verification. Please try again.',
        );
      }
    } finally {
      client.close();
    }
  }
}

abstract interface class LoginAttemptGuard {
  Future<void> verifyLogin({required String email, required String password});
}

class SupabaseLoginAttemptGuard implements LoginAttemptGuard {
  SupabaseLoginAttemptGuard({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<void> verifyLogin({
    required String email,
    required String password,
  }) async {
    final response = await _client.functions.invoke(
      'auth-account-check',
      body: {'email': email.trim(), 'password': password},
    );
    final data = response.data;
    if (data is! Map || data['allowed'] is! bool) {
      throw const AuthException(
        'Unable to verify your login. Please try again.',
      );
    }
    if (data['allowed'] != true) {
      final message = data['message']?.toString();
      throw AuthException(
        message == null || message.isEmpty
            ? 'Unable to verify your login. Please try again.'
            : message,
      );
    }
  }
}

class PersonalProfile {
  const PersonalProfile({
    required this.displayName,
    required this.email,
    required this.phoneNumber,
    this.avatarUrl,
    this.memberSince,
  });

  final String displayName;
  final String email;
  final String phoneNumber;
  final String? avatarUrl;
  final DateTime? memberSince;
}

class TravelHistoryEntry {
  const TravelHistoryEntry({
    required this.origin,
    required this.destination,
    required this.fare,
    required this.currency,
    required this.departureTime,
    required this.createdAt,
    required this.lineName,
    this.durationMinutes = 0,
    this.estimatedArrivalTime = '',
    this.transitSteps = const [],
  });

  factory TravelHistoryEntry.fromJson(Map<String, dynamic> json) {
    var lineName = 'Transit';
    final steps = json['transit_steps'];
    if (steps is List && steps.isNotEmpty) {
      Map<String, dynamic>? chosen;
      for (final step in steps) {
        if (step is Map && step['mode']?.toString().toLowerCase() == 'rail') {
          chosen = Map<String, dynamic>.from(step);
          break;
        }
      }
      if (chosen == null && steps.first is Map) {
        chosen = Map<String, dynamic>.from(steps.first as Map);
      }
      lineName = chosen?['name']?.toString() ?? 'Transit';
    }

    final transitSteps = steps is List
        ? steps
              .whereType<Map>()
              .map(
                (step) =>
                    TravelHistoryStep.fromJson(Map<String, dynamic>.from(step)),
              )
              .toList(growable: false)
        : const <TravelHistoryStep>[];

    return TravelHistoryEntry(
      origin: json['origin']?.toString() ?? 'Unknown',
      destination: json['destination']?.toString() ?? 'Unknown',
      fare: (json['fare'] as num?)?.toDouble() ?? 0,
      currency: json['currency']?.toString() ?? 'MYR',
      departureTime: json['departure_time']?.toString() ?? '',
      estimatedArrivalTime: json['estimated_arrival_time']?.toString() ?? '',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
      transitSteps: transitSteps,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
          DateTime.now(),
      lineName: lineName,
    );
  }

  final String origin;
  final String destination;
  final double fare;
  final String currency;
  final String departureTime;
  final DateTime createdAt;
  final String lineName;
  final int durationMinutes;
  final String estimatedArrivalTime;
  final List<TravelHistoryStep> transitSteps;
}

class TravelHistoryStep {
  const TravelHistoryStep({
    required this.mode,
    required this.name,
    required this.duration,
    required this.description,
  });

  factory TravelHistoryStep.fromJson(Map<String, dynamic> json) {
    return TravelHistoryStep(
      mode: json['mode']?.toString() ?? 'Transit',
      name: json['name']?.toString() ?? 'Transit',
      duration: json['duration']?.toString() ?? '',
      description: (json['description'] ?? json['desc'])?.toString() ?? '',
    );
  }

  final String mode;
  final String name;
  final String duration;
  final String description;
}

class RoutineSuggestion {
  const RoutineSuggestion({
    required this.origin,
    required this.destination,
    required this.tripCount,
    required this.commonWeekdays,
    required this.mostRecentTrip,
  });

  final String origin;
  final String destination;
  final int tripCount;
  final Set<int> commonWeekdays;
  final DateTime mostRecentTrip;

  String get routeKey => SmartRoutineService.routeKey(origin, destination);
}

class SmartRoutineService {
  SmartRoutineService(this._savedRoutesRepository, {ApiService? apiService})
    : _apiService = apiService ?? ApiService();

  static const int minimumTrips = 3;
  static const Duration historyPeriod = Duration(days: 30);

  final SavedRoutesRepository _savedRoutesRepository;
  final ApiService _apiService;

  static RoutineSuggestion? detect({
    required List<TravelHistoryEntry> history,
    Iterable<DailyCommuteRoute> configuredCommutes = const [],
    DateTime? now,
  }) {
    final cutoff = (now ?? DateTime.now()).subtract(historyPeriod);
    final groups = <String, List<TravelHistoryEntry>>{};
    for (final trip in history) {
      if (trip.createdAt.isBefore(cutoff) ||
          _normalise(trip.origin).isEmpty ||
          _normalise(trip.destination).isEmpty ||
          _normalise(trip.origin) == 'unknown' ||
          _normalise(trip.destination) == 'unknown') {
        continue;
      }
      groups
          .putIfAbsent(routeKey(trip.origin, trip.destination), () => [])
          .add(trip);
    }

    final candidates =
        groups.values.where((trips) {
          if (trips.length < minimumTrips) return false;
          final candidateKey = routeKey(
            trips.first.origin,
            trips.first.destination,
          );
          return !configuredCommutes.any(
            (commute) =>
                candidateKey == routeKey(commute.origin, commute.destination),
          );
        }).toList()..sort((a, b) {
          final countOrder = b.length.compareTo(a.length);
          if (countOrder != 0) return countOrder;
          final aLatest = a
              .map((trip) => trip.createdAt)
              .reduce((left, right) => left.isAfter(right) ? left : right);
          final bLatest = b
              .map((trip) => trip.createdAt)
              .reduce((left, right) => left.isAfter(right) ? left : right);
          return bLatest.compareTo(aLatest);
        });
    if (candidates.isEmpty) return null;

    final trips = candidates.first;
    final latest = trips
        .map((trip) => trip.createdAt)
        .reduce((left, right) => left.isAfter(right) ? left : right);
    return RoutineSuggestion(
      origin: trips.first.origin,
      destination: trips.first.destination,
      tripCount: trips.length,
      commonWeekdays: trips.map((trip) => trip.createdAt.weekday).toSet(),
      mostRecentTrip: latest,
    );
  }

  Future<SavedRoute> findOrCreateFavourite(RoutineSuggestion suggestion) async {
    var routes = await _savedRoutesRepository.load();
    final existing = _matchingRoute(routes, suggestion);
    if (existing != null) return existing;

    final stations = await _apiService.loadAllStations();
    final origin = _matchingStation(stations, suggestion.origin);
    final destination = _matchingStation(stations, suggestion.destination);
    if (origin == null || destination == null) {
      throw StateError(
        'This route can no longer be matched to the current station list. '
        'Save it in Favourite Routes first.',
      );
    }
    final routeOptions = await _apiService.findRoutes(origin, destination);
    if (routeOptions.isEmpty) {
      throw StateError('No current route is available for this routine.');
    }
    final option = routeOptions.first;
    final draft = SavedRoute(
      name: _favouriteName(origin.name, destination.name),
      origin: origin,
      destination: destination,
      signature: option['sig']?.toString() ?? '',
      lineName: option['name']?.toString() ?? 'Transit',
    );
    await _savedRoutesRepository.save(draft);
    routes = await _savedRoutesRepository.load();
    final saved = routes
        .where((route) => route.routeKey == draft.routeKey)
        .firstOrNull;
    if (saved?.id == null) {
      throw StateError('Unable to prepare this routine as a favourite route.');
    }
    return saved!;
  }

  static String routeKey(String origin, String destination) =>
      '${_normalise(origin)}\u0000${_normalise(destination)}';

  static SavedRoute? _matchingRoute(
    List<SavedRoute> routes,
    RoutineSuggestion suggestion,
  ) => routes
      .where(
        (route) =>
            route.id != null &&
            routeKey(route.origin.name, route.destination.name) ==
                suggestion.routeKey,
      )
      .firstOrNull;

  static StationModel? _matchingStation(
    List<StationModel> stations,
    String name,
  ) => stations
      .where((station) => _normalise(station.name) == _normalise(name))
      .firstOrNull;

  static String _favouriteName(String origin, String destination) {
    final name = '$origin to $destination';
    return name.length <= 80 ? name : '${name.substring(0, 77)}...';
  }

  static String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

class DailyCommuteRoute {
  const DailyCommuteRoute({required this.origin, required this.destination});

  final String origin;
  final String destination;
}

class PersonalTravelService {
  PersonalTravelService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client,
      _functions = PersonalAssistanceFunctions(client: client);

  final SupabaseClient _client;
  final PersonalAssistanceFunctions _functions;

  User get _user {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    return user;
  }

  Future<PersonalProfile> loadProfile({String? confirmedEmail}) async {
    final user = _user;
    final response = await _functions.invoke('personal-data', 'get-profile');
    final row = Map<String, dynamic>.from(response['data'] as Map);

    final name = (row['display_name'] as String?)?.trim();
    return PersonalProfile(
      displayName: name == null || name.isEmpty
          ? user.email ?? 'NextRoute User'
          : name,
      email: confirmedEmail ?? user.email ?? '',
      phoneNumber: row['phone_number'] as String? ?? '',
      avatarUrl: row['avatar_url'] as String?,
      memberSince: DateTime.tryParse(user.createdAt),
    );
  }

  Future<List<TravelHistoryEntry>> loadTravelHistory({int limit = 100}) async {
    final rows = await _functions.list(
      'journey-history',
      'list',
      payload: {'limit': limit, 'completed_only': true},
    );
    return rows.map(TravelHistoryEntry.fromJson).toList();
  }

  Future<void> updateProfile({String? displayName, String? phoneNumber}) async {
    final changes = <String, dynamic>{};
    if (displayName != null) changes['display_name'] = displayName;
    if (phoneNumber != null) changes['phone_number'] = phoneNumber;
    await _functions.invoke(
      'personal-data',
      'update-profile',
      payload: changes,
    );
  }

  Future<String> uploadAvatar(
    Uint8List bytes, {
    required String contentType,
  }) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Photo must be 5 MB or smaller.');
    }
    final response = await _functions.invoke(
      'profile-avatar',
      'upload',
      payload: {
        'content_type': contentType,
        'data_base64': base64Encode(bytes),
      },
    );
    return response['avatar_url'] as String;
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    PasswordCodeLogin? passwordLogin,
  }) async {
    final user = _user;
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw const AuthException('This account does not have an email address.');
    }
    await (passwordLogin ?? PasswordCodeLogin(auth: _client.auth))
        .verifyPassword(email: email, password: oldPassword);
    await _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<void> deleteAccount({required String confirmation}) async {
    if (confirmation != 'DELETE') {
      throw const FormatException('Type DELETE to confirm account deletion.');
    }

    final session = _client.auth.currentSession;
    if (session == null) throw const AuthException('Please sign in again.');
    final response = await _client.functions.invoke(
      'delete-account',
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
      body: {'confirmation': confirmation},
    );
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      final message = data is Map ? data['error']?.toString() : null;
      throw StateError(
        message == null || message.isEmpty
            ? 'Account deletion failed. Please try again.'
            : message,
      );
    }

    await _client.auth.signOut(scope: SignOutScope.local);
  }
}
