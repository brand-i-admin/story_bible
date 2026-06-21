// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필 헤더의 톱니바퀴 버튼이 여는 설정 모달 시트.
// - 개인정보 보호 (legal docs)
// - 지도 설명
// - 로그아웃
// - 하단: 관리자 문의 이메일 (admin@brand-i.net)
part of '../profile_tab_page.dart';

extension ProfileSettingsSheetExt on ProfileTabPageState {
  Future<void> _openProfileSettingsSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: SafeArea(
          top: false,
          child: Container(
            clipBehavior: Clip.hardEdge,
            decoration: modalSurfaceDecoration(),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '설정',
                    style: TextStyle(
                      color: Color(0xFF3A2B15),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _settingsRow(
                    icon: Icons.policy_outlined,
                    label: '개인정보 보호',
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _openLegalDocumentsPage();
                    },
                  ),
                  const SizedBox(height: 8),
                  _settingsRow(
                    icon: Icons.info_outline_rounded,
                    label: '지도 설명',
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      unawaited(showMapAttributionDialog(context));
                    },
                  ),
                  const SizedBox(height: 8),
                  _settingsRow(
                    icon: Icons.logout_rounded,
                    label: '로그아웃',
                    danger: true,
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _signOut();
                    },
                  ),
                  const SizedBox(height: 14),
                  Container(height: 1, color: const Color(0x448E6F48)),
                  const SizedBox(height: 10),
                  // 관리자 문의 이메일 — 안내성 푸터.
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mail_outline_rounded,
                        size: 14,
                        color: Color(0xFF8C6743),
                      ),
                      SizedBox(width: 6),
                      Text(
                        'admin@brand-i.net',
                        style: TextStyle(
                          color: Color(0xFF6A4C2E),
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Center(
                    child: Text(
                      '관리자 문의',
                      style: TextStyle(
                        color: Color(0xAA8C6743),
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final fg = danger ? const Color(0xFF8C4A3A) : const Color(0xFF3A2B15);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0x88F7E9D2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x66B89A66), width: 0.8),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: fg,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: fg.withValues(alpha: 0.55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
