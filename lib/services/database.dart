import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared entry point for Supabase Database, Auth, Storage and Realtime APIs.
abstract final class Database {
  static SupabaseClient get client => Supabase.instance.client;

  static Future<String> checkConnection() async {
    final row = await client
        .from('connection_test')
        .select('message')
        .eq('id', 1)
        .single();

    return row['message'] as String;
  }
}
