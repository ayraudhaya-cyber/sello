import 'package:shared_preferences/shared_preferences.dart';
import 'package:sello/services/updates/sello_build_meta.dart';
import 'package:sello/shared/models/app_version.dart';

/// Remembers which installed build the user already saw “Updated” highlights for.
///
/// The seen state is written to the shared key *and* the app-scoped key.
/// [appKey] comes from the signed-in role on web, so it is null before the
/// session restores; writing both keeps a dismissal sticky across that change.
class ReleaseHighlightsStore {
  ReleaseHighlightsStore({this.appKey});

  final String? appKey;

  static const _versionKey = 'sello.release_highlights.seen_version';
  static const _revisionKey = 'sello.release_highlights.seen_revision';

  List<String> get _versionKeys => [
        _versionKey,
        if (appKey != null) '$_versionKey.$appKey',
      ];

  List<String> get _revisionKeys => [
        _revisionKey,
        if (appKey != null) '$_revisionKey.$appKey',
      ];

  Future<String?> seenVersionIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    return _readAny(prefs, _versionKeys);
  }

  Future<String?> seenRevision() async {
    final prefs = await SharedPreferences.getInstance();
    return _readAny(prefs, _revisionKeys);
  }

  Future<void> markSeen({
    required AppVersion installed,
    String? revision,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _versionKeys) {
      await prefs.setString(key, installed.identity);
    }

    final rev = (revision ?? SelloBuildMeta.shortRevision)?.trim();
    for (final key in _revisionKeys) {
      if (rev == null || rev.isEmpty) {
        await prefs.remove(key);
      } else {
        await prefs.setString(key, rev);
      }
    }
  }

  /// First launch: remember quietly. Later launches: show when the build changed.
  Future<bool> shouldShowHighlights(AppVersion installed) async {
    final prefs = await SharedPreferences.getInstance();
    final current = installed.identity;
    final revision = SelloBuildMeta.shortRevision;

    final seenVersions = _readAll(prefs, _versionKeys);
    if (seenVersions.isEmpty) {
      await markSeen(installed: installed, revision: revision);
      return false;
    }

    if (!seenVersions.contains(current)) return true;

    // Same version label, but a new web/CI build landed (revision baked in).
    if (revision == null || revision.isEmpty) return false;

    final seenRevisions = _readAll(prefs, _revisionKeys);
    if (seenRevisions.isEmpty) {
      await markSeen(installed: installed, revision: revision);
      return false;
    }

    return !seenRevisions.contains(revision);
  }

  String? _readAny(SharedPreferences prefs, List<String> keys) {
    final values = _readAll(prefs, keys);
    return values.isEmpty ? null : values.last;
  }

  List<String> _readAll(SharedPreferences prefs, List<String> keys) {
    final values = <String>[];
    for (final key in keys) {
      final value = prefs.getString(key)?.trim();
      if (value != null && value.isNotEmpty) values.add(value);
    }
    return values;
  }
}
