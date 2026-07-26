import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/core/constants/app_constants.dart';
import 'package:sello/core/router/app_router.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/shared/providers/theme_mode_provider.dart';

class SelloApp extends ConsumerWidget {
  const SelloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      // Dark theme is architecturally wired; palette not implemented yet.
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
