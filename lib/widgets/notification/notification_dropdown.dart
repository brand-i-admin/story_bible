import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/app_notification.dart';
import '../../state/notification_providers.dart';
import '../../theme/app_color_palette.dart';
import '../story_home_styles.dart';
import 'notification_list_tile.dart';

/// bell 버튼 탭 시 열리는 드롭다운 패널.
///
/// - 읽지 않은 알림 최대 5개 표시 (서버 측 limit + only_unread=true).
/// - 하단 액션: "모두 읽음" / "전체 보기".
/// - 각 알림 탭 시 [onTapItem] 호출 → 호출자가 딥링크 라우팅 + 읽음 처리.
class NotificationDropdown extends ConsumerWidget {
  const NotificationDropdown({
    super.key,
    required this.onClose,
    required this.onTapItem,
    required this.onOpenHistory,
  });

  final VoidCallback onClose;
  final void Function(AppNotification notification) onTapItem;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPaletteTheme.of(context);
    final unreadAsync = ref.watch(unreadNotificationsProvider);
    return Container(
      width: 340,
      constraints: const BoxConstraints(maxHeight: 460),
      decoration: floatingPanelDecoration(
        color: palette.panelSurface,
        shadowOpacity: 0.22,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Header(onClose: onClose),
          Flexible(
            child: unreadAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  '알림을 불러오지 못했어요\n$err',
                  style: TextStyle(
                    fontSize: 12,
                    color: palette.currentAccentDeep,
                  ),
                ),
              ),
              data: (items) {
                if (items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 28,
                      horizontal: 18,
                    ),
                    child: Text(
                      '새로운 알림이 없어요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: palette.mutedText,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 1,
                    indent: 14,
                    endIndent: 14,
                    color: palette.subtleBorder,
                  ),
                  itemBuilder: (_, index) {
                    final n = items[index];
                    return NotificationListTile(
                      notification: n,
                      compact: true,
                      onTap: () => onTapItem(n),
                    );
                  },
                );
              },
            ),
          ),
          _Footer(
            onMarkAllRead: () async {
              final repo = ref.read(notificationRepositoryProvider);
              await repo.markAllRead();
              ref.invalidate(unreadNotificationsProvider);
              ref.invalidate(notificationHistoryProvider);
            },
            onOpenHistory: onOpenHistory,
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '알림',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: palette.text,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: onClose,
            icon: Icon(
              Icons.close_rounded,
              size: 20,
              color: palette.primaryDeep,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.onMarkAllRead, required this.onOpenHistory});
  final Future<void> Function() onMarkAllRead;
  final VoidCallback onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: palette.subtleBorder, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          TextButton(
            onPressed: onMarkAllRead,
            style: TextButton.styleFrom(
              foregroundColor: palette.primaryDeep,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: const Text('모두 읽음'),
          ),
          const Spacer(),
          TextButton(
            onPressed: onOpenHistory,
            style: TextButton.styleFrom(
              foregroundColor: palette.primaryDeep,
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: const Text('전체 보기'),
          ),
        ],
      ),
    );
  }
}
