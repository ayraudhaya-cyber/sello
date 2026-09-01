/// Public Supabase client configuration from compile-time dart-defines.
///
/// Never hardcode URL or keys. Never ship a service-role key in the app.
///
/// Provide values with `--dart-define` or `--dart-define-from-file` (see BUILD.md):
/// - `SUPABASE_URL`
/// - `SUPABASE_ANON_KEY` (preferred) or `SUPABASE_PUBLISHABLE_KEY`
abstract final class SupabaseConfig {
  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );

  /// Supabase project URL, e.g. `https://xxxx.supabase.co`.
  static String get url {
    final value = _url.trim();
    if (value.isEmpty) {
      throw StateError(
        'Missing SUPABASE_URL. Pass --dart-define=SUPABASE_URL=... '
        'or --dart-define-from-file (see BUILD.md).',
      );
    }
    return value;
  }

  /// Supabase anon / publishable key for client-side access.
  static String get publishableKey {
    final value = _resolvedKey;
    if (value.isEmpty) {
      throw StateError(
        'Missing SUPABASE_ANON_KEY (or SUPABASE_PUBLISHABLE_KEY). '
        'Pass --dart-define or --dart-define-from-file (see BUILD.md).',
      );
    }
    return value;
  }

  static String get _resolvedKey {
    final anon = _anonKey.trim();
    if (anon.isNotEmpty) return anon;
    return _publishableKey.trim();
  }

  /// True when both required values look configured (not placeholders).
  static bool get isConfigured {
    final u = _url.trim();
    final k = _resolvedKey;
    if (u.isEmpty || k.isEmpty) return false;
    if (u.contains('your-project')) return false;
    if (k.contains('your-publishable-key') || k.contains('your-anon-key')) {
      return false;
    }
    return true;
  }
}
