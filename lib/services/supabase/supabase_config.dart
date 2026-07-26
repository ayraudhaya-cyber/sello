import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Reads Supabase credentials from environment (via flutter_dotenv).
///
/// Never hardcode URL or keys. Source of truth:
/// - `.env` for local/runtime values (gitignored)
/// - `.env.example` for documentation / fallback template
abstract final class SupabaseConfig {
  static const _urlKey = 'SUPABASE_URL';
  static const _publishableKeyKey = 'SUPABASE_PUBLISHABLE_KEY';

  /// Supabase project URL, e.g. `https://xxxx.supabase.co`.
  static String get url {
    final value = dotenv.maybeGet(_urlKey)?.trim() ?? '';
    if (value.isEmpty) {
      throw StateError(
        'Missing $_urlKey. Add it to `.env` (see `.env.example`).',
      );
    }
    return value;
  }

  /// Supabase publishable (anon) key for client-side access.
  static String get publishableKey {
    final value = dotenv.maybeGet(_publishableKeyKey)?.trim() ?? '';
    if (value.isEmpty) {
      throw StateError(
        'Missing $_publishableKeyKey. Add it to `.env` (see `.env.example`).',
      );
    }
    return value;
  }

  /// True when both required env values look configured (not placeholders).
  static bool get isConfigured {
    final u = dotenv.maybeGet(_urlKey)?.trim() ?? '';
    final k = dotenv.maybeGet(_publishableKeyKey)?.trim() ?? '';
    if (u.isEmpty || k.isEmpty) return false;
    if (u.contains('your-project')) return false;
    if (k.contains('your-publishable-key') || k.contains('your-anon-key')) {
      return false;
    }
    return true;
  }
}
