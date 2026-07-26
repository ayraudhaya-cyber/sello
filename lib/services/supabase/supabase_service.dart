import 'package:flutter/foundation.dart';
import 'package:sello/services/supabase/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Production entry point for the Supabase Flutter client.
///
/// Responsibilities:
/// - Initialize once before [runApp]
/// - Expose a typed accessor for the shared [SupabaseClient]
///
/// Does not own auth flows, repositories, or domain logic.
abstract final class SupabaseService {
  static bool _initialized = false;

  static bool get isInitialized => _initialized;

  /// Initializes Supabase using [SupabaseConfig] from dotenv.
  ///
  /// Must be called after `dotenv.load(...)` and before `runApp`.
  static Future<void> initialize() async {
    if (_initialized) {
      debugPrint('SupabaseService: already initialized — skipping.');
      return;
    }

    if (!SupabaseConfig.isConfigured) {
      throw StateError(
        'Supabase is not configured. '
        'Copy `.env.example` to `.env` and set SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY.',
      );
    }

    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );

    _initialized = true;
    debugPrint('SupabaseService: initialized (${_redactedUrl(SupabaseConfig.url)})');
  }

  /// Shared Supabase client. Throws if [initialize] has not completed.
  static SupabaseClient get client {
    if (!_initialized) {
      throw StateError(
        'SupabaseService.client used before initialize(). '
        'Call SupabaseService.initialize() in main().',
      );
    }
    return Supabase.instance.client;
  }

  static String _redactedUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (_) {
      return '(invalid-url)';
    }
  }
}
