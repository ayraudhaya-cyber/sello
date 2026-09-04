import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/services/pwa/pwa_install_bridge.dart';
import 'package:sello/services/pwa/pwa_install_policy.dart';

class PwaInstallState {
  const PwaInstallState({
    this.mode = PwaInstallMode.hidden,
    this.isPrompting = false,
    this.canInvokePrompt = false,
  });

  final PwaInstallMode mode;
  final bool isPrompting;

  /// Native `prompt()` is callable right now (deferred event present).
  final bool canInvokePrompt;

  bool get shouldShow =>
      mode == PwaInstallMode.promptAvailable || mode == PwaInstallMode.iosManual;

  PwaInstallState copyWith({
    PwaInstallMode? mode,
    bool? isPrompting,
    bool? canInvokePrompt,
  }) {
    return PwaInstallState(
      mode: mode ?? this.mode,
      isPrompting: isPrompting ?? this.isPrompting,
      canInvokePrompt: canInvokePrompt ?? this.canInvokePrompt,
    );
  }
}

class PwaInstallController extends Notifier<PwaInstallState> {
  StreamSubscription<void>? _installableSub;
  StreamSubscription<void>? _installedSub;

  @override
  PwaInstallState build() {
    ref.onDispose(() {
      _installableSub?.cancel();
      _installedSub?.cancel();
    });

    _installableSub = PwaInstallBridge.onInstallable.listen((_) => refresh());
    _installedSub = PwaInstallBridge.onInstalled.listen((_) => refresh());

    return _snapshot();
  }

  void refresh() {
    state = _snapshot(isPrompting: state.isPrompting);
  }

  Future<PwaInstallPromptResult> install() async {
    if (state.mode != PwaInstallMode.promptAvailable || state.isPrompting) {
      return PwaInstallPromptResult.unavailable;
    }
    if (!PwaInstallBridge.canPrompt) {
      // Prompt was already used (e.g. user cancelled). Card stays visible;
      // browser may re-fire beforeinstallprompt shortly.
      return PwaInstallPromptResult.unavailable;
    }
    state = state.copyWith(isPrompting: true);
    final result = await PwaInstallBridge.promptInstall();
    state = _snapshot(isPrompting: false);
    return result;
  }

  PwaInstallState _snapshot({bool isPrompting = false}) {
    final canPrompt = PwaInstallBridge.canPrompt;
    return PwaInstallState(
      mode: PwaInstallPolicy.resolve(
        isWeb: PwaInstallBridge.isWeb,
        isStandalone: PwaInstallBridge.isStandalone,
        canPrompt: canPrompt,
        isAppleMobile: PwaInstallBridge.isAppleMobile,
        installUiEligible: PwaInstallBridge.isInstallUiEligible,
      ),
      isPrompting: isPrompting,
      canInvokePrompt: canPrompt,
    );
  }
}

final pwaInstallProvider =
    NotifierProvider<PwaInstallController, PwaInstallState>(
  PwaInstallController.new,
);
