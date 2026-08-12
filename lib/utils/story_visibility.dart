import '../models/era.dart';
import '../models/story_event.dart';
import 'bible_book_meta.dart';

/// 공개 전인 성경 권. 운영 DB에서는 관련 사건을 `draft`로 두고,
/// 앱도 배포 시점 차이를 견디도록 같은 정책으로 한 번 더 걸러낸다.
const hiddenStoryBibleBookNames = <String>{'요한계시록'};

bool storyEventUsesHiddenBibleBook(StoryEvent event) {
  return bibleBookKeysUseHiddenBook(
    event.bibleRefs.map((reference) => reference.book),
  );
}

bool bibleBookKeysUseHiddenBook(Iterable<String> bookKeys) {
  return canonicalBibleBookNames(
    bookKeys,
  ).any(hiddenStoryBibleBookNames.contains);
}

bool rawBibleRefsUseHiddenBook(Object? rawBibleRefs) {
  if (rawBibleRefs is! List) return false;
  return bibleBookKeysUseHiddenBook(
    rawBibleRefs.whereType<Map>().map(
      (reference) => reference['book']?.toString() ?? '',
    ),
  );
}

bool isStoryEventVisibleInApp(
  StoryEvent event, {
  required Map<String, Era> eraById,
}) {
  final eraCode = eraById[event.eraId]?.code;
  if (eraCode != null && isHiddenEraCode(eraCode)) return false;
  return !storyEventUsesHiddenBibleBook(event);
}

List<StoryEvent> visibleStoryEvents({
  required Iterable<StoryEvent> events,
  required Iterable<Era> eras,
}) {
  final eraById = {for (final era in eras) era.id: era};
  return events
      .where((event) => isStoryEventVisibleInApp(event, eraById: eraById))
      .toList(growable: false);
}
