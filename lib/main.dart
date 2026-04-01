import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

const _runtimeEnv = String.fromEnvironment('ENV', defaultValue: 'dev');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final supabaseConfig = _resolveSupabaseConfig();

  await Supabase.initialize(
    url: supabaseConfig.url,
    anonKey: supabaseConfig.anonKey,
  );

  runApp(const ProviderScope(child: StoryBibleApp()));
}

SupabaseConfig _resolveSupabaseConfig() {
  final normalizedEnv = _runtimeEnv.toLowerCase();
  // Temporary release workaround:
  // Keep prod builds pointed to the same dev Supabase project.
  final suffix = switch (normalizedEnv) {
    'dev' => 'DEV',
    'prod' => 'DEV',
    _ => throw StateError(
      'Unsupported ENV="$_runtimeEnv". Use ENV=dev or ENV=prod.',
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
