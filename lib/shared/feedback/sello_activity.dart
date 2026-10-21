import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Screen state that is in the middle of a user-started save.
abstract interface class SelloBusyState {
  bool get isBusy;
}

/// How many user-started saves are in flight.
///
/// Domain notifiers report this through [SelloActivityObserver]. Call
/// [run] for a save that does not go through one of those notifiers.
abstract final class SelloActivity {
  static final ValueNotifier<int> depth = ValueNotifier<int>(0);
  static int _depth = 0;

  static void begin() {
    _depth++;
    depth.value = _depth;
  }

  static void end() {
    if (_depth == 0) return;
    _depth--;
    depth.value = _depth;
  }

  static Future<T> run<T>(Future<T> Function() action) async {
    begin();
    try {
      return await action();
    } finally {
      end();
    }
  }
}

/// Turns each notifier's busy flag into one [SelloActivity] count.
class SelloActivityObserver extends ProviderObserver {
  final Set<ProviderBase<Object?>> _active = {};

  @override
  void didUpdateProvider(
    ProviderBase<Object?> provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    final busy = newValue is SelloBusyState && newValue.isBusy;
    final tracked = _active.contains(provider);
    if (busy && !tracked) {
      _active.add(provider);
      SelloActivity.begin();
    } else if (!busy && tracked) {
      _active.remove(provider);
      SelloActivity.end();
    }
  }

  @override
  void didDisposeProvider(
    ProviderBase<Object?> provider,
    ProviderContainer container,
  ) {
    if (_active.remove(provider)) {
      SelloActivity.end();
    }
  }
}
