import 'package:sello/services/supabase/supabase_service.dart';
import 'package:sello/services/updates/release_app_kind.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

/// Reads the public one-row release document from Supabase.
///
/// Used when no file URL is compiled into the binary (typical Android/iOS APK).
class SupabaseReleaseManifestSource {
  const SupabaseReleaseManifestSource();

  Future<SelloReleaseManifest?> fetch({ReleaseAppKind? app}) async {
    if (!SupabaseService.isInitialized) return null;
    try {
      final row = await SupabaseService.client
          .from('sello_app_release')
          .select('payload')
          .eq('id', 1)
          .maybeSingle();
      return SelloReleaseManifest.tryParse(row?['payload'], app: app);
    } catch (_) {
      return null;
    }
  }
}
