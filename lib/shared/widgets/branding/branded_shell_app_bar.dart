import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/theme/theme.dart';
import 'package:sello/shared/providers/branding_provider.dart';
import 'package:sello/shared/widgets/navigation/sello_navigation.dart';

/// Shell app bar: Sello-light by default, Hub-rail chrome when the tenant
/// uses a reverse wordmark or custom nav colour.
class BrandedShellAppBar extends ConsumerWidget implements PreferredSizeWidget {
  const BrandedShellAppBar({
    super.key,
    this.actions,
    this.leading,
    this.hub = false,
    this.size = 32,
    this.centerTitle = false,
    this.compactMark = false,
  });

  final List<Widget>? actions;
  final Widget? leading;
  final bool hub;
  final double size;
  final bool centerTitle;
  final bool compactMark;

  @override
  Size get preferredSize => const Size.fromHeight(AppSpacing.topBarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branding = ref.watch(brandingProvider);
    final darkChrome =
        branding.hasCustomLogo || branding.hasCustomNavBackground;

    return AppBar(
      backgroundColor: darkChrome ? Colors.transparent : AppColors.surface,
      foregroundColor: darkChrome ? AppColors.onPrimary : AppColors.textPrimary,
      iconTheme: IconThemeData(
        color: darkChrome ? AppColors.onPrimary : AppColors.textPrimary,
      ),
      actionsIconTheme: IconThemeData(
        color: darkChrome ? AppColors.onPrimary : AppColors.textSecondary,
      ),
      systemOverlayStyle: darkChrome
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      automaticallyImplyLeading: leading == null,
      leading: leading,
      centerTitle: centerTitle,
      titleSpacing: centerTitle ? 0 : NavigationToolbar.kMiddleSpacing,
      flexibleSpace: darkChrome
          ? SizedBox.expand(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: context.selloColors.navRail,
                ),
              ),
            )
          : null,
      title: SelloBrandMark(
        hub: hub,
        compact: compactMark,
        size: size,
        light: darkChrome,
        alignment: centerTitle ? Alignment.center : Alignment.centerLeft,
      ),
      actions: actions,
    );
  }
}
