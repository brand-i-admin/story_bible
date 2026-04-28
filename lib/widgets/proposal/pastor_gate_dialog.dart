import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 사역자(is_pastor=true) 가 아닌 사용자가 "이야기 등록" 탭을 눌렀을 때 뜨는
/// 안내 다이얼로그.
///
/// 운영 정책: 외부 사역자가 직접 가입만 해서는 제안 권한이 없다.
/// admin@brand-i.net 으로 신원(성함/사역 단체/직책) 을 보내면 관리자가
/// Supabase 대시보드에서 수동으로 `user_profiles.is_pastor = true` 로 토글.
class PastorGateDialog extends StatelessWidget {
  const PastorGateDialog({super.key});

  static const String _contactEmail = 'admin@brand-i.net';

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const PastorGateDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.church_outlined, size: 36),
      title: const Text('사역자 인증이 필요합니다'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '성경 이야기는 사역자분들만 요청하실 수 있습니다.\n'
            '사역자 분들께서는 아래 이메일로 \n'
            '• 성함\n'
            '• 사역하는 단체\n'
            '• 직책\n'
            '을 보내주시면 확인 후 권한을 부여해드립니다.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          Material(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                await Clipboard.setData(
                  const ClipboardData(text: _contactEmail),
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('이메일 주소가 복사되었습니다'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.email_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _contactEmail,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.copy, size: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('알겠습니다'),
        ),
      ],
    );
  }
}
