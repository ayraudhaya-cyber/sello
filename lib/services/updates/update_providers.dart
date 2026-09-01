import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/services/session/session_provider.dart';
import 'package:sello/services/updates/app_version_reader.dart';
import 'package:sello/services/updates/release_app_kind.dart';
import 'package:sello/services/updates/release_manifest_config.dart';
import 'package:sello/services/updates/update_check_cache.dart';
import 'package:sello/services/updates/update_check_service.dart';
import 'package:sello/shared/models/app_version.dart';
import 'package:sello/shared/models/sello_release_manifest.dart';

final appVersionReaderProvider = Provider<AppVersionReader>(
  (ref) => const PackageInfoVersionReader(),
);

final installedAppVersionProvider = FutureProvider<AppVersion>((ref) {
  return ref.watch(appVersionReaderProvider).read();
});

/// Sales Rep vs Owner/Manager: compile-time APK identity, else signed-in role.
final releaseAppKindProvider = Provider<ReleaseAppKind?>((ref) {
  final compiled = ReleaseManifestConfig.compiledReleaseApp;
  if (compiled != null) return compiled;
  final session = ref.watch(currentSessionProvider);
  if (session == null) return null;
  return ReleaseAppKind.fromUserRole(session.appRole);
});

final updateCheckServiceProvider = Provider<UpdateCheckService>((ref) {
  final app = ref.watch(releaseAppKindProvider);
  return UpdateCheckService(
    versionReader: ref.watch(appVersionReaderProvider),
    cache: UpdateCheckCache(appKey: app?.jsonKey),
    platform: ReleaseManifestConfig.currentPlatform,
    releaseApp: app,
  );
});

class UpdateCheckController extends AsyncNotifier<UpdateCheckSnapshot> {
  var promptEvenIfPostponed = false;

  @override
  Future<UpdateCheckSnapshot> build() {
    return ref.watch(updateCheckServiceProvider).check();
  }

  Future<UpdateCheckSnapshot> checkNow() async {
    promptEvenIfPostponed = true;
    final previous = state;
    state = AsyncLoading<UpdateCheckSnapshot>().copyWithPrevious(previous);
    final result = await ref.read(updateCheckServiceProvider).check(force: true);
    state = AsyncData(result);
    return result;
  }

  Future<void> postpone() async {
    final current = state.valueOrNull;
    if (current == null) return;
    await ref.read(updateCheckServiceProvider).postpone(current);
  }

  Future<bool> isPostponed(UpdateCheckSnapshot snapshot) {
    return ref.read(updateCheckServiceProvider).isPromptPostponed(snapshot);
  }
}

final updateCheckControllerProvider =
    AsyncNotifierProvider<UpdateCheckController, UpdateCheckSnapshot>(
  UpdateCheckController.new,
);
