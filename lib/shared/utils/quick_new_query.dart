import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens a create/action flow once when the route includes `?new=1`.
///
/// Used by Hub / Sales pages so Quick Actions can deeplink into the same
/// editors already owned by those pages — no duplicated create logic.
///
/// After the flag is consumed the URL is cleaned; that clears the latch so a
/// later Quick Action to the same page can open the editor again.
mixin QuickNewQueryMixin<T extends StatefulWidget> on State<T> {
  bool _quickNewOpened = false;

  /// Call from [didChangeDependencies].
  void consumeQuickNewQuery({
    required String cleanPath,
    required VoidCallback open,
  }) {
    final flag = GoRouterState.of(context).uri.queryParameters['new'];
    if (flag != '1' && flag != 'true') {
      // Clean URL (or unrelated nav) — allow the next ?new=1 to fire.
      _quickNewOpened = false;
      return;
    }
    if (_quickNewOpened) return;
    _quickNewOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      open();
      context.go(cleanPath);
    });
  }
}
