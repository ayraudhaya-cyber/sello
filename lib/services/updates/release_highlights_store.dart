import 'package:shared_preferences/shared_preferences.dart';
import 'package:sello/services/updates/sello_build_meta.dart';
import 'package:sello/shared/models/app_version.dart';

/// Remembers which installed build the user already saw “Updated” highlights for.
class ReleaseHighlightsStore {
  ReleaseHighlightsStore({this.appKey});

  final String? appKey;

  static const _versionKey = 'sello.release_highlights.seen_version';
  static const _revisionKey = 'sello.release_highlights.seen_revision';

  String get _scopedVersionKey =>
      appKey == null ? _versionKey : '$_versionKey.$appKey';

  String get _scopedRevisionKey =>
      appKey == null ? _revisionKey : '$_revisionKey.$appKey';

  Future<String?> seenVersionIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_scopedVersionKey)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<String?> seenRevision() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_scopedRevisionKey)?.trim();
    return (value == null || value.isEmpty) ? null : value;
  }

  Future<void> markSeen({
    required AppVersion installed,
    String? revision,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_scopedVersionKey, installed.identity);
    final rev = (revision ?? SelloBuildMeta.shortRevision)?.trim();
    if (rev == null || rev.isEmpty) {
      await prefs.remove(_scopedRevisionKey);
    } else {
      await prefs.setString(_scopedRevisionKey, rev);
    }
  }

  /// First launch: remember quietly. Later launches: show when the build changed.
  Future<bool> shouldShowHighlights(AppVersion installed) async {
    final seen = await seenVersionIdentity();
    final current = installed.identity;
    final revision = SelloBuildMeta.shortRevision;

    if (seen == null) {
      await markSeen(installed: installed, revision: revision);
      return false;
    }

    if (seen != current) return true;

    // Same version label, but a new web/CI build landed (revision baked in).
    if (revision != null && revision.isNotEmpty) {
      final seenRev = await seenRevision();
      if (seenRev == null) {
        await markSeen(installed: installed, revision: revision);
        return false;
      }
      if (seenRev != revision) return true;
    }

    return false;
  }
}
