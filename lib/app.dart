import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/constants/app_constants.dart';
import 'package:sello/core/router/app_router.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/devtools/dev_experience.dart';
import 'package:sello/features/updates/presentation/update_check_host.dart';
import 'package:sello/shared/providers/branding_provider.dart';
import 'package:sello/shared/providers/theme_mode_provider.dart';
import 'package:sello/shared/widgets/feedback/sello_toast.dart';

class SelloApp extends ConsumerWidget {
  const SelloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final branding = ref.watch(brandingProvider);
    final theme = AppTheme.themed(branding);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: theme,
      // Dark theme is architecturally wired; palette not implemented yet.
      darkTheme: theme,
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) {
        return wrapWithDevExperience(
          SelloToastHost(
            child: UpdateCheckHost(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
