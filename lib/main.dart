import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:sello/app.dart';
import 'package:sello/core/theme/app_theme.dart';
import 'package:sello/features/system/presentation/system_pages.dart';
import 'package:sello/services/reliability/reliability_providers.dart';
import 'package:sello/services/supabase/supabase.dart';
import 'package:sello/services/updates/update_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  if (!SupabaseConfig.isConfigured) {
    runApp(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const AppErrorPage(
          title: 'Supabase is not configured',
          message:
              'Run with --dart-define-from-file=.env, or use the Sello (debug) '
              'launch configuration. See BUILD.md.',
        ),
      ),
    );
    return;
  }

  await SupabaseService.initialize();

  // Session restoration (auth + AppSession) runs inside AuthSessionNotifier.
  // Reliability bootstrap (connectivity + sync) starts with the first frame.
  runApp(
    ProviderScope(
      child: Consumer(
        builder: (context, ref, _) {
          ref.watch(reliabilityBootstrapProvider);
          ref.watch(updateCheckControllerProvider);
          return const SelloApp();
        },
      ),
    ),
  );
}
