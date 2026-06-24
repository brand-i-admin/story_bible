import '../models/story_event.dart';

/// A curated timeline section available inside one era.
///
/// These values are stored on each [StoryEvent] row and reused by proposal
/// screens so pastors choose an existing section instead of inventing codes.
class TimelineUnitOption {
  const TimelineUnitOption({
    required this.code,
    required this.title,
    required this.order,
    this.eventCount = 0,
    this.firstStoryIndex = 0,
  });

  final String code;
  final String title;
  final int order;
  final int eventCount;
  final int firstStoryIndex;

  String get displayTitle => '$order. $title';
}

class _TimelineUnitAccumulator {
  _TimelineUnitAccumulator({
    required this.code,
    required this.title,
    required this.order,
    required this.firstStoryIndex,
  });

  final String code;
  String title;
  int order;
  int eventCount = 0;
  int firstStoryIndex;

  void add(StoryEvent event) {
    eventCount += 1;
    final nextOrder = event.unitOrder <= 0 ? 1 : event.unitOrder;
    if (event.storyIndex > 0 &&
        (firstStoryIndex == 0 || event.storyIndex < firstStoryIndex)) {
      firstStoryIndex = event.storyIndex;
    }
    if (nextOrder < order) {
      order = nextOrder;
    }
    final nextTitle = _normalizedTitle(event.unitTitle);
    if (title == _defaultTitle && nextTitle != _defaultTitle) {
      title = nextTitle;
    }
  }

  TimelineUnitOption toOption() {
    return TimelineUnitOption(
      code: code,
      title: title,
      order: order,
      eventCount: eventCount,
      firstStoryIndex: firstStoryIndex,
    );
  }
}

/// Builds era-local timeline unit options from existing published events.
///
/// [selectedFallback] is only for editing a pending proposal whose saved unit
/// no longer appears in published events. New proposals should pass null.
List<TimelineUnitOption> timelineUnitOptionsForEvents(
  Iterable<StoryEvent> events, {
  TimelineUnitOption? selectedFallback,
}) {
  final byCode = <String, _TimelineUnitAccumulator>{};
  for (final event in events) {
    final code = _normalizedCode(event.unitCode);
    final existing = byCode[code];
    if (existing == null) {
      byCode[code] = _TimelineUnitAccumulator(
        code: code,
        title: _normalizedTitle(event.unitTitle),
        order: event.unitOrder <= 0 ? 1 : event.unitOrder,
        firstStoryIndex: event.storyIndex,
      )..add(event);
    } else {
      existing.add(event);
    }
  }

  if (selectedFallback != null &&
      selectedFallback.code.trim().isNotEmpty &&
      !byCode.containsKey(selectedFallback.code.trim())) {
    byCode[selectedFallback.code.trim()] = _TimelineUnitAccumulator(
      code: selectedFallback.code.trim(),
      title: _normalizedTitle(selectedFallback.title),
      order: selectedFallback.order <= 0 ? 1 : selectedFallback.order,
      firstStoryIndex: selectedFallback.firstStoryIndex,
    );
  }

  final options = byCode.values.map((entry) => entry.toOption()).toList();
  options.sort(
    (a, b) => a.order.compareTo(b.order) != 0
        ? a.order.compareTo(b.order)
        : a.firstStoryIndex.compareTo(b.firstStoryIndex) != 0
        ? a.firstStoryIndex.compareTo(b.firstStoryIndex)
        : a.code.compareTo(b.code),
  );
  return options;
}

const _defaultCode = 'default';
const _defaultTitle = '전체 흐름';

String _normalizedCode(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? _defaultCode : trimmed;
}

String _normalizedTitle(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? _defaultTitle : trimmed;
}
