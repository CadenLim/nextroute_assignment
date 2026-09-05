import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import 'api_service.dart';

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

abstract class SavedRoutesRepository {
  Future<List<SavedRoute>> load();
  Future<int> count();
  Future<void> save(SavedRoute route);
  Future<void> rename(String id, String name);
  Future<void> delete(String id);
}

class SupabaseSavedRoutesRepository implements SavedRoutesRepository {
  SupabaseSavedRoutesRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String get _userId {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthException('Please sign in again.');
    return id;
  }

  @override
  Future<List<SavedRoute>> load() async {
    final rows = await _client
        .from('saved_routes')
        .select()
        .eq('user_id', _userId)
        .order('created_at', ascending: false);
    return rows.map(SavedRoute.fromJson).toList();
  }

  @override
  Future<int> count() => _client
      .from('saved_routes')
      .count(CountOption.exact)
      .eq('user_id', _userId);

  @override
  Future<void> save(SavedRoute route) async {
    _validateName(route.name);
    await _client
        .from('saved_routes')
        .upsert(
          route.toInsert(_userId),
          onConflict: 'user_id,route_key',
          ignoreDuplicates: true,
        );
  }

  @override
  Future<void> rename(String id, String name) async {
    _validateName(name);
    await _client
        .from('saved_routes')
        .update({'name': name.trim()})
        .eq('id', id)
        .eq('user_id', _userId)
        .select('id')
        .single();
  }

  @override
  Future<void> delete(String id) async {
    await _client
        .from('saved_routes')
        .delete()
        .eq('id', id)
        .eq('user_id', _userId)
        .select('id')
        .single();
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
  }) : _projectUrl = projectUrl ?? SupabaseConfig.url,
       _publishableKey = publishableKey ?? SupabaseConfig.publishableKey,
       _passwordClientFactory = passwordClientFactory ?? http.Client.new;

  final GoTrueClient auth;
  final String _projectUrl;
  final String _publishableKey;
  final http.Client Function() _passwordClientFactory;

  Future<void> sendCode({
    required String email,
    required String password,
  }) async {
    await verifyPassword(email: email, password: password);
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

    return TravelHistoryEntry(
      origin: json['origin']?.toString() ?? 'Unknown',
      destination: json['destination']?.toString() ?? 'Unknown',
      fare: (json['fare'] as num?)?.toDouble() ?? 0,
      currency: json['currency']?.toString() ?? 'MYR',
      departureTime: json['departure_time']?.toString() ?? '',
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
}

class PersonalTravelService {
  PersonalTravelService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  User get _user {
    final user = _client.auth.currentUser;
    if (user == null) throw const AuthException('Please sign in again.');
    return user;
  }

  Future<PersonalProfile> loadProfile({String? confirmedEmail}) async {
    final user = _user;
    Map<String, dynamic> row;
    try {
      row = await _client
          .from('profiles')
          .select('display_name, phone_number, avatar_path')
          .eq('id', user.id)
          .single();
    } on PostgrestException catch (error) {
      if (error.code != '42703') rethrow;
      row = await _client
          .from('profiles')
          .select('display_name, phone_number')
          .eq('id', user.id)
          .single();
    }

    final name = (row['display_name'] as String?)?.trim();
    final avatarPath = row['avatar_path'] as String?;
    String? avatarUrl;
    if (avatarPath != null && avatarPath.isNotEmpty) {
      final signed = await _client.storage
          .from('avatars')
          .createSignedUrl(avatarPath, 3600);
      avatarUrl = '$signed&v=${DateTime.now().millisecondsSinceEpoch}';
    }
    return PersonalProfile(
      displayName: name == null || name.isEmpty
          ? user.email ?? 'NextRoute User'
          : name,
      email: confirmedEmail ?? user.email ?? '',
      phoneNumber: row['phone_number'] as String? ?? '',
      avatarUrl: avatarUrl,
      memberSince: DateTime.tryParse(user.createdAt),
    );
  }

  Future<List<TravelHistoryEntry>> loadTravelHistory({int limit = 100}) async {
    final rows = await _client
        .from('navigation_history')
        .select()
        .eq('user_id', _user.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(TravelHistoryEntry.fromJson).toList();
  }

  Future<String> uploadAvatar(
    Uint8List bytes, {
    required String contentType,
  }) async {
    if (bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Photo must be 5 MB or smaller.');
    }
    final user = _user;
    final path = '${user.id}/avatar';
    await _client.storage
        .from('avatars')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(upsert: true, contentType: contentType),
        );
    await _client
        .from('profiles')
        .update({
          'avatar_path': path,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', user.id)
        .select('id')
        .single();
    final signed = await _client.storage
        .from('avatars')
        .createSignedUrl(path, 3600);
    return '$signed&v=${DateTime.now().millisecondsSinceEpoch}';
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
}
