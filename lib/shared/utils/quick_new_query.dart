import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Opens a create/action flow once when the route includes `?new=1`.
///
/// Used by Hub / Sales pages so Quick Actions can deeplink into the same
/// editors already owned by those pages — no duplicated create logic.
mixin QuickNewQueryMixin<T extends StatefulWidget> on State<T> {
  bool _quickNewOpened = false;

  /// Call from [didChangeDependencies].
  void consumeQuickNewQuery({
    required String cleanPath,
    required VoidCallback open,
  }) {
    if (_quickNewOpened) return;
    final flag = GoRouterState.of(context).uri.queryParameters['new'];
    if (flag != '1' && flag != 'true') return;
    _quickNewOpened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      open();
      context.go(cleanPath);
    });
  }
}
