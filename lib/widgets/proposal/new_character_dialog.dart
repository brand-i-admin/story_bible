import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/proposal_repository.dart';
import '../../models/event_proposal.dart';
import '../../state/proposal_providers.dart';

/// 제안 작성 Step 2 에서 "기존 characters 에 없는 새 인물" 을 만들기 위한 다이얼로그.
///
/// - 이름 (한글) + 코드 (영문 snake_case, 자동 제안) + 프롬프트 입력
/// - [이미지 생성] 버튼 → Edge Function 호출 → 미리보기
/// - 마음에 들면 [이 인물 추가] 로 확정
///
/// 반환값: 확정 시 [ProposedCharacter] (코드/이름/프롬프트/storage_path),
/// 취소 시 null.
///
/// 재생성은 같은 드래프트+코드로 다시 호출하면 덮어쓰기 (Edge Function upsert:true).
class NewCharacterDialog extends ConsumerStatefulWidget {
  const NewCharacterDialog({
    super.key,
    required this.draftId,
    required this.existingCodes,
  });

  /// 제안의 drafts 식별자. 여러 장면 이미지 + 이 인물 모두 같은 폴더 사용.
  final String draftId;

  /// 이미 선택된 / 제안 중인 character code 목록. 중복 방지.
  final Set<String> existingCodes;

  /// 편의 메서드. `await NewCharacterDialog.show(context, ...)`.
  static Future<ProposedCharacter?> show(
    BuildContext context, {
    required String draftId,
    required Set<String> existingCodes,
  }) {
    return showDialog<ProposedCharacter>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          NewCharacterDialog(draftId: draftId, existingCodes: existingCodes),
    );
  }

  @override
  ConsumerState<NewCharacterDialog> createState() => _NewCharacterDialogState();
}

class _NewCharacterDialogState extends ConsumerState<NewCharacterDialog> {
  final _nameCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _promptCtrl = TextEditingController();
  // 사용자가 작성한 공개용 한글 설명 — 홈 화면 인물 카드의 우측 본문에 표시.
  // AI 생성용 prompt(_promptCtrl) 와 분리한 이유: prompt 는 "지팡이를 든 ..." +
  // COMMON_STYLE 영문 토큰이 섞여 사용자에게 보이기엔 부적합.
  final _descCtrl = TextEditingController();
  bool _userEditedCode = false;
  bool _generating = false;
  String? _errorText;
  GeneratedProposalCharacter? _result;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_autoFillCode);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_autoFillCode);
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _promptCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  /// 이름을 입력할 때 code 가 비어 있으면 자동으로 snake_case 코드 제안.
  /// 사용자가 code 를 직접 수정한 이후에는 건드리지 않는다.
  void _autoFillCode() {
    if (_userEditedCode) return;
    final suggestion = _slugify(_nameCtrl.text);
    if (_codeCtrl.text != suggestion) {
      _codeCtrl.text = suggestion;
    }
  }

  static String _slugify(String input) {
    final t = input.trim().toLowerCase();
    if (t.isEmpty) return '';
    // 한글/공백 → '_' 로. 영문/숫자/_ 는 보존.
    final sb = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      final code = c.codeUnitAt(0);
      final isAsciiAlnum =
          (code >= 0x30 && code <= 0x39) || (code >= 0x61 && code <= 0x7A);
      if (isAsciiAlnum || c == '_') {
        sb.write(c);
      } else {
        sb.write('_');
      }
    }
    var out = sb.toString();
    // 연속 _ 압축 + 양끝 trim
    while (out.contains('__')) {
      out = out.replaceAll('__', '_');
    }
    if (out.startsWith('_')) out = out.substring(1);
    if (out.endsWith('_')) out = out.substring(0, out.length - 1);
    return out.substring(0, out.length > 48 ? 48 : out.length);
  }

  bool get _canGenerate {
    if (_generating) return false;
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return false;
    // 서버 sanitize 와 동일 규칙 — 빈 결과로 떨어질 입력은 미리 차단.
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(code)) return false;
    if (_promptCtrl.text.trim().isEmpty) return false;
    return true;
  }

  Future<void> _onGenerate() async {
    final code = _codeCtrl.text.trim();
    if (widget.existingCodes.contains(code)) {
      setState(() {
        _errorText = '이미 사용 중인 코드 "$code" 입니다. 다른 코드를 쓰세요.';
      });
      return;
    }
    setState(() {
      _generating = true;
      _errorText = null;
    });
    try {
      final repo = ref.read(proposalRepositoryProvider);
      final result = await repo.generateProposalCharacter(
        prompt: _promptCtrl.text.trim(),
        characterCode: code,
        characterName: _nameCtrl.text.trim(),
        draftId: widget.draftId,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _onConfirm() {
    final result = _result;
    if (result == null) return;
    final desc = _descCtrl.text.trim();
    Navigator.of(context).pop(
      ProposedCharacter(
        code: result.characterCode,
        name: _nameCtrl.text.trim().isEmpty
            ? result.characterCode
            : _nameCtrl.text.trim(),
        prompt: result.prompt,
        storagePath: result.storagePath,
        description: desc.isEmpty ? null : desc,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final repo = ref.read(proposalRepositoryProvider);
    return AlertDialog(
      title: const Text('새 인물 만들기'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'AI 가 기존 인물 그림체와 같은 스타일로 새 인물 아바타를 만들어 줍니다. '
                '아래 설명을 바탕으로 생성되며, 마음에 안 들면 "다시 생성" 으로 재시도 가능합니다.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '이름 (한글)',
                  hintText: '예: 갈렙의 제자',
                ),
                enabled: !_generating,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _codeCtrl,
                inputFormatters: [
                  // 영문 소문자/숫자/밑줄만 허용. 한글·대문자·공백·특수문자 차단.
                  FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9_]')),
                ],
                decoration: const InputDecoration(
                  labelText: '영문 코드 (snake_case)',
                  hintText: '예: caleb_disciple',
                  helperText: '소문자/숫자/밑줄만. 이름 입력 시 자동 제안됩니다.',
                ),
                onChanged: (_) => _userEditedCode = true,
                enabled: !_generating,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _promptCtrl,
                maxLines: 4,
                minLines: 3,
                decoration: const InputDecoration(
                  labelText: '인물 설명 (AI 가 참고할 프롬프트)',
                  hintText: '예: 30대 남성, 어두운 곱슬머리, 거친 아마천 튜닉, 지팡이를 든 목자의 분위기',
                  helperText: 'AI 이미지 생성용 — 사용자에게는 보이지 않아요.',
                ),
                enabled: !_generating,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: '인물 한 줄 소개 (홈 화면 카드에 표시)',
                  hintText: '예: 갈렙을 따라 가나안 정탐에 나선 젊은 제자.',
                  helperText: '선택 — 비워두면 위 프롬프트가 대신 사용됩니다.',
                ),
                enabled: !_generating,
              ),
              const SizedBox(height: 14),
              _PreviewPanel(
                generating: _generating,
                result: _result,
                repo: repo,
              ),
              if (_errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorText!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _generating ? null : () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.tonalIcon(
          onPressed: _canGenerate ? _onGenerate : null,
          icon: Icon(
            _result == null ? Icons.auto_awesome : Icons.refresh,
            size: 18,
          ),
          label: Text(_result == null ? '이미지 생성' : '다시 생성'),
        ),
        FilledButton.icon(
          onPressed: _result == null || _generating ? null : _onConfirm,
          icon: const Icon(Icons.check, size: 18),
          label: const Text('이 인물 추가'),
        ),
      ],
    );
  }
}

class _PreviewPanel extends StatelessWidget {
  const _PreviewPanel({
    required this.generating,
    required this.result,
    required this.repo,
  });

  final bool generating;
  final GeneratedProposalCharacter? result;
  final ProposalRepository repo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Center(
        child: generating
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'AI 가 그림을 생성중입니다',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '한 번에 한 장만 생성됩니다. 잠시만 기다려주세요.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : result == null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 44,
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '아직 생성된 이미지가 없습니다',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  repo.publicUrlForStoragePath(result!.storagePath),
                  fit: BoxFit.contain,
                  height: 200,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 44),
                ),
              ),
      ),
    );
  }
}
