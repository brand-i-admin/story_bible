import 'package:flutter/material.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/push_service.dart';
import 'state/font_scale_providers.dart';

const _runtimeEnv = String.fromEnvironment('ENV', defaultValue: 'dev');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final supabaseConfig = _resolveSupabaseConfig();

  await Supabase.initialize(
    url: supabaseConfig.url,
    anonKey: supabaseConfig.anonKey,
  );

  // Firebase / FCM 초기화 — Firebase 프로젝트가 아직 설정되지 않은 환경에서도
  // 앱이 죽지 않도록 try-catch 로 감싼다. `flutterfire configure` 가 완료되면
  // 자동으로 동작한다 (docs/PUSH_SETUP.md).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await PushService.instance.initialize();
  } catch (e) {
    debugPrint('[push] Firebase 비활성 상태 — 푸시 알림 없이 진행합니다: $e');
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
  final suffix = switch (normalizedEnv) {
    'dev' => 'DEV',
    'prod' || 'real' => 'PROD',
    _ => throw StateError(
      'Unsupported ENV="$_runtimeEnv". Use ENV=dev, ENV=real, or ENV=prod.',
    ),
  };

  final url = dotenv.env['SUPABASE_URL_$suffix'];
  final anonKey = dotenv.env['SUPABASE_ANON_KEY_$suffix'];

  if (url == null || url.isEmpty) {
    throw StateError('Missing SUPABASE_URL_$suffix in .env');
  }
  if (anonKey == null || anonKey.isEmpty) {
    throw StateError('Missing SUPABASE_ANON_KEY_$suffix in .env');
  }

  return SupabaseConfig(url: url, anonKey: anonKey);
}

class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;
}
