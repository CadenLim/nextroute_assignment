abstract final class SupabaseConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  static void validate() {
    final uri = Uri.tryParse(url);
    final hasValidUrl =
        uri != null &&
        (uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host.isNotEmpty;

    if (!hasValidUrl || publishableKey.isEmpty) {
      throw StateError(
        'Supabase is not configured. Start Flutter with '
        '--dart-define-from-file=config/supabase.json. See README.md.',
      );
    }
  }
}
