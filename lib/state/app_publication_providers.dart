import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/app_publication_repository.dart';
import '../models/app_publication.dart';
import 'story_controller.dart';

final appPublicationRepositoryProvider = Provider<AppPublicationRepository>((
  ref,
) {
  return AppPublicationRepository(ref.watch(supabaseClientProvider));
});

final publishedAppPublicationsProvider =
    FutureProvider.autoDispose<List<AppPublication>>((ref) {
      return ref
          .watch(appPublicationRepositoryProvider)
          .fetchPublishedPublications();
    });
