import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_publication.dart';

class AppPublicationRepository {
  AppPublicationRepository(this._client);

  final SupabaseClient _client;

  Future<List<AppPublication>> fetchPublishedPublications({
    int limit = 50,
  }) async {
    final rows = await _client
        .from('app_publications')
        .select()
        .eq('is_published', true)
        .order('display_order', ascending: true)
        .order('published_at', ascending: false)
        .limit(limit);

    return rows.map<AppPublication>(AppPublication.fromMap).toList();
  }
}
