import 'package:sello/services/updates/app_version_reader.dart';
import 'package:sello/services/updates/release_app_kind.dart';
import 'package:sello/services/updates/release_manifest_client.dart';
import 'package:sello/services/updates/supabase_release_manifest_source.dart';
import 'package:sello/services/updates/update_check_cache.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

/// Compares the installed binary to the remote Sello release manifest.
///
/// Network and parse failures never throw to the UI — they return
/// [UpdateCheckStatus.checkFailed] so the user can keep working.
class UpdateCheckService {
  UpdateCheckService({
    AppVersionReader? versionReader,
    ReleaseManifestClient? client,
    UpdateCheckCache? cache,
    Future<SelloReleaseManifest?> Function()? fallbackManifest,
    this.platform = AppReleasePlatform.other,
    this.releaseApp,
    this.manifestUrl,
  })  : _versions = versionReader ?? const PackageInfoVersionReader(),
        _client = client ?? ReleaseManifestClient(),
        _cache = cache ?? UpdateCheckCache(),
        _fallbackManifest = fallbackManifest;

  final AppVersionReader _versions;
  final ReleaseManifestClient _client;
  final UpdateCheckCache _cache;
  final Future<SelloReleaseManifest?> Function()? _fallbackManifest;
  final AppReleasePlatform platform;
  final ReleaseAppKind? releaseApp;
  final String? manifestUrl;

  Future<AppVersion> installedVersion() => _versions.read();

  Future<bool> isPromptPostponed(UpdateCheckSnapshot snapshot) async {
    if (snapshot.status != UpdateCheckStatus.updateAvailable) return false;
    final postponed = await _cache.postponedIdentity();
    final latest = snapshot.latest?.identity;
    if (postponed == null || latest == null) return false;
    return postponed == _postponeKey(latest);
  }

  Future<void> postpone(UpdateCheckSnapshot snapshot) async {
    final identity = snapshot.latest?.identity;
    if (identity == null || identity.isEmpty) return;
    await _cache.postpone(_postponeKey(identity));
  }

  String _postponeKey(String latestIdentity) {
    final app = releaseApp?.jsonKey ?? 'unknown';
    return '$app:$latestIdentity';
  }

  Future<UpdateCheckSnapshot> check({bool force = false}) async {
    final installed = await _versions.read();
    if (releaseApp == null) {
      return UpdateCheckSnapshot.failed(
        installed: installed,
        reason: 'Release information is not configured.',
      );
    }

    if (!force) {
      final cached = await _usableCache(installed);
      if (cached != null) return cached;
    }

    try {
      final manifest = await _loadManifest();
      final status = UpdatePolicy.resolve(
        installed: installed,
        manifest: manifest,
      );
      final snapshot = UpdateCheckSnapshot(
        status: status,
        installed: installed,
        latest: manifest.latest,
        minimum: manifest.minimum,
        notes: manifest.notes,
        releasedAt: manifest.releasedAt,
        channel: manifest.channelFor(platform),
        checkedAt: DateTime.now().toUtc(),
      );
      await _cache.save(snapshot);
      return snapshot;
    } on ReleaseManifestFetchException catch (error) {
      return UpdateCheckSnapshot.failed(
        installed: installed,
        reason: error.message,
      );
    } catch (_) {
      return UpdateCheckSnapshot.failed(
        installed: installed,
        reason: 'Unable to check for updates.',
      );
    }
  }

  Future<SelloReleaseManifest> _loadManifest() async {
    try {
      return await _client.fetch(url: manifestUrl, app: releaseApp);
    } on ReleaseManifestFetchException {
      final fallback = _fallbackManifest ??
          () => const SupabaseReleaseManifestSource().fetch(app: releaseApp);
      final resolved = await fallback();
      if (resolved != null) return resolved;
      rethrow;
    }
  }

  Future<UpdateCheckSnapshot?> _usableCache(AppVersion installed) async {
    if (!await _cache.isFresh()) return null;
    final cached = await _cache.load();
    if (cached == null) return null;
    if (cached.status == UpdateCheckStatus.updateRequired) return null;
    if (cached.status == UpdateCheckStatus.checkFailed) return null;
    if (cached.installed != installed) return null;
    return cached;
  }
}
