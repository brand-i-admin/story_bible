import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/app_monitoring_service.dart';
import 'services/push_service.dart';
import 'state/font_scale_providers.dart';

const _runtimeEnv = String.fromEnvironment('ENV', defaultValue: 'dev');
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var firebaseReady = false;
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    firebaseReady = true;
    await AppMonitoringService.instance.initialize(
      runtimeEnvironment: _runtimeEnv,
    );
  } catch (error) {
    debugPrint('[firebase] Firebase 비활성 상태로 진행합니다: $error');
  }

  final supabaseConfig = _resolveSupabaseConfig();
  await Supabase.initialize(
    url: supabaseConfig.url,
    anonKey: supabaseConfig.anonKey,
  );

  if (firebaseReady) {
    await AppMonitoringService.instance.observeAuthState(
      Supabase.instance.client,
    );
    try {
      await PushService.instance.initialize();
    } catch (error, stackTrace) {
      AppMonitoringService.instance.recordNonFatal(
        error,
        stackTrace,
        reason: 'Push service initialization failed',
      );
      debugPrint('[push] 푸시 초기화 실패 — 푸시 없이 진행합니다: $error');
    }
  }

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const StoryBibleApp(),
    ),
  );
}

SupabaseConfig _resolveSupabaseConfig() {
  final normalizedEnv = _runtimeEnv.toLowerCase();
  switch (normalizedEnv) {
    case 'dev':
    case 'prod':
    case 'real':
      break;
    default:
      throw StateError(
        'Unsupported ENV="$_runtimeEnv". Use ENV=dev, ENV=real, or ENV=prod.',
      );
  }

  final url = _supabaseUrl.trim();
  final anonKey = _supabaseAnonKey.trim();

  if (url.isEmpty) {
    throw StateError(
      'Missing --dart-define=SUPABASE_URL for ENV=$_runtimeEnv. '
      'Use scripts/run_dev.sh or scripts/run_real.sh.',
    );
  }
  if (anonKey.isEmpty) {
    throw StateError(
      'Missing --dart-define=SUPABASE_ANON_KEY for ENV=$_runtimeEnv. '
      'Use scripts/run_dev.sh or scripts/run_real.sh.',
    );
  }

  return SupabaseConfig(url: url, anonKey: anonKey);
}

class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;
}
