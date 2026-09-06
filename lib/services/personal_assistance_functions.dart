import 'package:supabase_flutter/supabase_flutter.dart';

/// Authenticated gateway for Personal Assistance Edge Functions.
///
/// The Flutter app only sends the current user's access token. Database
/// credentials remain in the Edge Function environment.
class PersonalAssistanceFunctions {
  PersonalAssistanceFunctions({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<Map<String, dynamic>> invoke(
    String functionName,
    String action, {
    Map<String, dynamic> payload = const {},
  }) async {
    final session = _client.auth.currentSession;
    if (session == null) throw const AuthException('Please sign in again.');

    final response = await _client.functions.invoke(
      functionName,
      headers: {'Authorization': 'Bearer ${session.accessToken}'},
      body: {'action': action, ...payload},
    );
    if (response.status < 200 || response.status >= 300) {
      final responseData = response.data;
      final message = responseData is Map
          ? responseData['error']?.toString()
          : null;
      throw StateError(
        message == null || message.isEmpty
            ? 'Unable to complete the request. Please try again.'
            : message,
      );
    }

    final data = response.data;
    if (data is! Map) throw const FormatException('Invalid server response.');
    return Map<String, dynamic>.from(data);
  }

  Future<List<Map<String, dynamic>>> list(
    String functionName,
    String action, {
    Map<String, dynamic> payload = const {},
  }) async {
    final response = await invoke(functionName, action, payload: payload);
    final data = response['data'];
    if (data is! List) throw const FormatException('Invalid server response.');
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }
}
