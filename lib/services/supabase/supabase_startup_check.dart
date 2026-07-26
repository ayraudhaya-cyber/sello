import 'package:flutter/foundation.dart';
import 'package:sello/services/supabase/supabase_service.dart';

/// Temporary startup verification against Migration 001 seeded data.
///
/// Reads `public.roles` and logs rows to the debug console.
/// Remove or replace once repositories / health checks exist.
abstract final class SupabaseStartupCheck {
  static Future<void> verifyRolesSeed() async {
    if (!SupabaseService.isInitialized) {
      debugPrint('SupabaseStartupCheck: skipped — Supabase not initialized.');
      return;
    }

    try {
      final rows = await SupabaseService.client
          .from('roles')
          .select('code, name, display_order')
          .order('display_order', ascending: true);

      final list = List<Map<String, dynamic>>.from(rows as List);

      debugPrint('────────────────────────────────────────');
      debugPrint('SupabaseStartupCheck: roles table OK (${list.length} rows)');
      for (final row in list) {
        debugPrint(
          '  • [${row['display_order']}] ${row['code']} — ${row['name']}',
        );
      }
      debugPrint('────────────────────────────────────────');
    } catch (error, stackTrace) {
      debugPrint('SupabaseStartupCheck: FAILED to read roles');
      debugPrint('  error: $error');
      debugPrint('  stack: $stackTrace');
    }
  }
}
