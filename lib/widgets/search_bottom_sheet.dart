import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/story_event.dart';
import '../state/story_controller.dart';

/// 이벤트 검색 결과를 표시하는 바텀 시트 내용.
///
/// [showEventSearchSheet]를 통해 [showModalBottomSheet]로 띄우며, 결과를
/// 선택하면 [onResultSelected]가 호출된다. 상세 화면 열기, 상위 상태 전환 같은
/// 후속 동작은 호출측에서 처리한다.
class EventSearchSheet extends ConsumerWidget {
  const EventSearchSheet({
    super.key,
    required this.onResultSelected,
    required this.maxHeight,
  });

  final void Function(StoryEvent event) onResultSelected;
  final double maxHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaQuery = MediaQuery.of(context);
    final state = ref.watch(storyControllerProvider);
    final controller = ref.read(storyControllerProvider.notifier);
    final results = controller.searchResults();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        14,
        12,
        mediaQuery.viewInsets.bottom + 14,
      ),
      child: SizedBox(
        height: maxHeight,
        child: Column(
          children: [
            TextFormField(
              key: ValueKey(state.searchQuery),
              initialValue: state.searchQuery,
              autofocus: true,
              onChanged: controller.setSearchQuery,
              decoration: InputDecoration(
                hintText: '단어/문장 검색...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            if (state.isSearching)
              const SizedBox(
                height: 28,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            Expanded(
              child: results.isEmpty
                  ? const Center(child: Text('검색 결과가 없습니다.'))
                  : ListView.separated(
                      itemCount: results.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final event = results[index];
                        return ListTile(
                          dense: true,
                          title: Text(event.title),
                          subtitle: Text(event.placeName ?? '-'),
                          onTap: () async {
                            await controller.selectSearchResult(event);
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                            onResultSelected(event);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 검색 바텀 시트를 연다. 결과 선택 시 [onResultSelected] 콜백을 호출.
Future<void> showEventSearchSheet({
  required BuildContext context,
  required void Function(StoryEvent event) onResultSelected,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: const Color(0xFFF5E9D6),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (context) {
      final mediaQuery = MediaQuery.of(context);
      final safeHeight =
          mediaQuery.size.height -
          mediaQuery.padding.top -
          mediaQuery.padding.bottom;
      final maxSheetHeight = math.min(
        mediaQuery.orientation == Orientation.landscape ? 520.0 : 560.0,
        safeHeight - 20,
      );
      return EventSearchSheet(
        onResultSelected: onResultSelected,
        maxHeight: maxSheetHeight,
      );
    },
  );
}
