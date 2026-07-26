import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sello/app.dart';
import 'package:sello/services/supabase/supabase.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // 1) Environment — must load before SupabaseConfig is read.
  await _loadEnv();

  // 2) Supabase client — before runApp.
  await SupabaseService.initialize();

  // 3) Temporary connectivity / schema smoke check (roles seed).
  await SupabaseStartupCheck.verifyRolesSeed();

  runApp(const ProviderScope(child: SelloApp()));
}

/// Loads `.env` first; falls back to `.env.example` for template-only runs.
Future<void> _loadEnv() async {
  try {
    await dotenv.load(fileName: '.env');
    debugPrint('dotenv: loaded `.env`');
  } catch (error) {
    debugPrint('dotenv: `.env` not loaded ($error) — trying `.env.example`');
    await dotenv.load(fileName: '.env.example');
    debugPrint('dotenv: loaded `.env.example`');
  }
}
