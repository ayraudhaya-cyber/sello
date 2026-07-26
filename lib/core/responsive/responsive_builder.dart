import 'package:flutter/widgets.dart';
import 'package:sello/core/responsive/app_breakpoints.dart';
import 'package:sello/core/responsive/responsive_context.dart';

/// Builds a different subtree per window size — never stretch one layout.
class ResponsiveBuilder extends StatelessWidget {
  const ResponsiveBuilder({
    super.key,
    required this.mobile,
    this.tablet,
    this.desktop,
  });

  final WidgetBuilder mobile;
  final WidgetBuilder? tablet;
  final WidgetBuilder? desktop;

  @override
  Widget build(BuildContext context) {
    return switch (context.windowSize) {
      AppWindowSize.mobile => mobile(context),
      AppWindowSize.tablet => (tablet ?? mobile)(context),
      AppWindowSize.desktop => (desktop ?? tablet ?? mobile)(context),
    };
  }
}

/// Shows [child] only when the current window matches [sizes].
class ResponsiveVisibility extends StatelessWidget {
  const ResponsiveVisibility({
    super.key,
    required this.sizes,
    required this.child,
    this.replacement = const SizedBox.shrink(),
  });

  final Set<AppWindowSize> sizes;
  final Widget child;
  final Widget replacement;

  @override
  Widget build(BuildContext context) {
    return sizes.contains(context.windowSize) ? child : replacement;
  }
}
