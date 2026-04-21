import 'package:flutter/material.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

const _runtimeEnv = String.fromEnvironment('ENV', defaultValue: 'dev');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final config = _resolveSupabaseConfig();
  await Supabase.initialize(url: config.url, anonKey: config.anonKey);

  runApp(const ProviderScope(child: AdminApp()));
}

class _Cfg {
  const _Cfg(this.url, this.anonKey);
  final String url;
  final String anonKey;
}

_Cfg _resolveSupabaseConfig() {
  final suffix = switch (_runtimeEnv.toLowerCase()) {
    'dev' => 'DEV',
    'prod' || 'real' => 'PROD',
    _ => throw StateError('Unsupported ENV="$_runtimeEnv"'),
  };
  final url = dotenv.env['SUPABASE_URL_$suffix'];
  final key = dotenv.env['SUPABASE_ANON_KEY_$suffix'];
  if (url == null || url.isEmpty) {
    throw StateError('Missing SUPABASE_URL_$suffix in .env');
  }
  if (key == null || key.isEmpty) {
    throw StateError('Missing SUPABASE_ANON_KEY_$suffix in .env');
  }
  return _Cfg(url, key);
}
