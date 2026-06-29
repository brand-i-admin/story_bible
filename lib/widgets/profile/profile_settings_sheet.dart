// 부모 라이브러리: lib/widgets/profile_tab_page.dart
//
// 프로필 헤더의 톱니바퀴 버튼이 여는 설정 모달 시트.
// - 개인정보 보호 (legal docs)
// - 지도 설명
// - 로그아웃
// - 계정 삭제
// - 하단: 관리자 문의 이메일 (admin@brand-i.net)
part of '../profile_tab_page.dart';

enum _ProfileSettingsAction { privacy, mapAttribution, signOut, deleteAccount }

extension ProfileSettingsSheetExt on ProfileTabPageState {
  Future<void> _openProfileSettingsSheet() async {
    final action = await showModalBottomSheet<_ProfileSettingsAction>(
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
                      Navigator.of(
                        sheetCtx,
                      ).pop(_ProfileSettingsAction.privacy);
                    },
                  ),
                  const SizedBox(height: 8),
                  _settingsRow(
                    icon: Icons.info_outline_rounded,
                    label: '지도 설명',
                    onTap: () {
                      Navigator.of(
                        sheetCtx,
                      ).pop(_ProfileSettingsAction.mapAttribution);
                    },
                  ),
                  const SizedBox(height: 8),
                  _settingsRow(
                    icon: Icons.logout_rounded,
                    label: '로그아웃',
                    danger: true,
                    onTap: () {
                      Navigator.of(
                        sheetCtx,
                      ).pop(_ProfileSettingsAction.signOut);
                    },
                  ),
                  const SizedBox(height: 8),
                  _settingsRow(
                    icon: Icons.delete_forever_rounded,
                    label: '계정 삭제',
                    danger: true,
                    onTap: () {
                      Navigator.of(
                        sheetCtx,
                      ).pop(_ProfileSettingsAction.deleteAccount);
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

    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _ProfileSettingsAction.privacy:
        await _openLegalDocumentsPage();
      case _ProfileSettingsAction.mapAttribution:
        unawaited(showMapAttributionDialog(context));
      case _ProfileSettingsAction.signOut:
        await _signOut();
      case _ProfileSettingsAction.deleteAccount:
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (mounted) {
          await _openDeleteAccountDialog();
        }
    }
  }

  Future<void> _openDeleteAccountDialog() async {
    final user = ref.read(signedInUserProvider);
    if (user == null || _deletingAccount || !mounted) {
      return;
    }

    final expectedId = accountDeletionConfirmationId(
      user: user,
      profile: _profileUser,
    );

    final deleted = await showDialog<bool>(
      context: context,
      builder: (_) => _DeleteAccountDialog(
        expectedId: expectedId,
        onDelete: (input) async {
          _setDeletingAccount(true);
          try {
            await ref
                .read(authRepositoryProvider)
                .deleteCurrentAccount(confirmationId: input);
          } finally {
            _setDeletingAccount(false);
          }
        },
      ),
    );

    if (deleted == true && mounted) {
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('계정 삭제가 완료되었습니다.')));
    }
  }

  Widget _settingsRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final fg = danger ? const Color(0xFF8C4A3A) : const Color(0xFF3A2B15);
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: BoxConstraints(minHeight: largeText ? 62 : 50),
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
                  maxLines: largeText ? 2 : 1,
                  overflow: largeText
                      ? TextOverflow.visible
                      : TextOverflow.ellipsis,
                  softWrap: true,
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

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog({
    required this.expectedId,
    required this.onDelete,
  });

  final String expectedId;
  final Future<void> Function(String input) onDelete;

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final TextEditingController _controller = TextEditingController();
  String _input = '';
  bool _submitting = false;
  String? _errorText;

  bool get _canDelete =>
      accountDeletionConfirmationMatches(
        input: _input,
        expected: widget.expectedId,
      ) &&
      !_submitting;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canDelete) {
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });

    try {
      await widget.onDelete(_input);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorText = '$error';
          _submitting = false;
        });
      }
    }
  }

  void _cancel() {
    if (_submitting) {
      return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_submitting,
      child: Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: Container(
            decoration: modalSurfaceDecoration(),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFF9C3F2E),
                        size: 22,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '계정 삭제',
                          style: TextStyle(
                            color: Color(0xFF3A2B15),
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '계정을 삭제하면 프로필과 학습 기록이 복구할 수 없게 삭제됩니다.',
                    style: TextStyle(
                      color: Color(0xFF4C3822),
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '삭제되는 정보: 프로필, 프로필 이미지, 저장한 이야기와 말씀, 본문 읽기/퀴즈/감정 기록, 동행 일지, 기도 연결, 알림과 푸시 토큰, 제안 작성 중 올린 이미지',
                    style: TextStyle(
                      color: Color(0xFF6A4C2E),
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      height: 1.42,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0x99FFF8EA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x88B89A66)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '삭제하려면 아래 입력란에 이 아이디를 그대로 입력해 주세요.',
                          style: TextStyle(
                            color: Color(0xFF5C4227),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          widget.expectedId,
                          style: const TextStyle(
                            color: AppColors.ink700,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    enabled: !_submitting,
                    textInputAction: TextInputAction.done,
                    onChanged: (value) {
                      setState(() {
                        _input = value;
                        _errorText = null;
                      });
                    },
                    onSubmitted: (_) => unawaited(_submit()),
                    decoration: InputDecoration(
                      labelText: '계정 확인 아이디 입력',
                      hintText: widget.expectedId,
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xBBFFF8EA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  if (_errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _errorText!,
                      style: const TextStyle(
                        color: Color(0xFFA63F2D),
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _submitting ? null : _cancel,
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF9C3F2E),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _canDelete
                              ? () => unawaited(_submit())
                              : null,
                          child: Text(_submitting ? '삭제 중...' : '계정 삭제'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
