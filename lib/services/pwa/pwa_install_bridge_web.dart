import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:sello/services/pwa/pwa_install_policy.dart';
import 'package:web/web.dart' as web;

@JS('selloPwa')
external _SelloPwaJs? get _selloPwa;

@JS()
@staticInterop
class _SelloPwaJs {}

extension _SelloPwaJsExt on _SelloPwaJs {
  external bool isStandalone();
  external bool canPrompt();
  external bool isInstallUiEligible();
  external bool isAppleMobile();
  external bool isIosSafari();
  external JSPromise<JSString> promptInstall();
}

/// Browser bridge to `web/pwa_install.js`.
abstract final class PwaInstallBridge {
  static StreamController<void>? _installableController;
  static StreamController<void>? _installedController;
  static web.EventListener? _installableListener;
  static web.EventListener? _installedListener;

  static bool get isWeb => true;

  static bool get isStandalone {
    final api = _selloPwa;
    if (api == null) return _fallbackStandalone();
    try {
      return api.isStandalone();
    } catch (_) {
      return _fallbackStandalone();
    }
  }

  static bool get canPrompt {
    final api = _selloPwa;
    if (api == null) return false;
    try {
      return api.canPrompt();
    } catch (_) {
      return false;
    }
  }

  static bool get isInstallUiEligible {
    final api = _selloPwa;
    if (api == null) return false;
    try {
      return api.isInstallUiEligible();
    } catch (_) {
      // Older bridge during hot reload — fall back to canPrompt.
      return canPrompt;
    }
  }

  static bool get isAppleMobile {
    final api = _selloPwa;
    if (api == null) return false;
    try {
      try {
        return api.isAppleMobile();
      } catch (_) {
        return api.isIosSafari();
      }
    } catch (_) {
      return false;
    }
  }

  static Future<PwaInstallPromptResult> promptInstall() async {
    final api = _selloPwa;
    if (api == null) return PwaInstallPromptResult.unavailable;
    try {
      final value = (await api.promptInstall().toDart).toDart;
      return switch (value) {
        'accepted' => PwaInstallPromptResult.accepted,
        'dismissed' => PwaInstallPromptResult.dismissed,
        _ => PwaInstallPromptResult.unavailable,
      };
    } catch (_) {
      return PwaInstallPromptResult.unavailable;
    }
  }

  static Stream<void> get onInstallable =>
      _cachedStream(
        controller: () => _installableController,
        setController: (c) => _installableController = c,
        listener: () => _installableListener,
        setListener: (l) => _installableListener = l,
        type: 'sello-pwa-installable',
      );

  static Stream<void> get onInstalled =>
      _cachedStream(
        controller: () => _installedController,
        setController: (c) => _installedController = c,
        listener: () => _installedListener,
        setListener: (l) => _installedListener = l,
        type: 'sello-pwa-installed',
      );

  static bool _fallbackStandalone() {
    try {
      if (web.window.matchMedia('(display-mode: standalone)').matches) {
        return true;
      }
      if (web.window.matchMedia('(display-mode: fullscreen)').matches) {
        return true;
      }
      if (web.window.matchMedia('(display-mode: minimal-ui)').matches) {
        return true;
      }
    } catch (_) {}
    try {
      final value =
          (web.window.navigator as JSObject).getProperty('standalone'.toJS);
      if (value.isA<JSBoolean>()) {
        return (value as JSBoolean).toDart;
      }
    } catch (_) {}
    return false;
  }

  static Stream<void> _cachedStream({
    required StreamController<void>? Function() controller,
    required void Function(StreamController<void>) setController,
    required web.EventListener? Function() listener,
    required void Function(web.EventListener?) setListener,
    required String type,
  }) {
    var existing = controller();
    if (existing != null) return existing.stream;

    late final StreamController<void> created;
    created = StreamController<void>.broadcast(
      onListen: () {
        final l = (web.Event _) {
          if (!created.isClosed) created.add(null);
        }.toJS;
        setListener(l);
        web.window.addEventListener(type, l);
      },
      onCancel: () {
        final l = listener();
        if (l != null) {
          web.window.removeEventListener(type, l);
          setListener(null);
        }
      },
    );
    setController(created);
    return created.stream;
  }
}
