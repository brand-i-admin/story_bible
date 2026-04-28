import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/story_event.dart';
import '../../state/proposal_providers.dart';

/// 사역자(pastor) 또는 관리자가 기존 이야기의 삭제 제안을 낼 때 띄우는 모달.
///
/// 사유(≥1자) 입력 → `submit_delete_proposal` RPC 호출 → 성공 시 스낵바 + 닫힘.
/// 같은 target 에 이미 pending 삭제 제안이 있으면 서버가 partial unique index
/// 위반을 던지고, 여기서 잡아 친근한 한국어 메시지로 노출한다.
///
/// 실제 삭제(events.deleted_at set)는 관리자 승인 시점에 `approve_delete_proposal`
/// 이 수행한다. 이 위젯은 "제안 제출" 까지만 담당한다.
class DeleteEventProposalSheet extends ConsumerStatefulWidget {
  const DeleteEventProposalSheet({super.key, required this.event});

  final StoryEvent event;

  @override
  ConsumerState<DeleteEventProposalSheet> createState() =>
      _DeleteEventProposalSheetState();
}

class _DeleteEventProposalSheetState
    extends ConsumerState<DeleteEventProposalSheet> {
  final _reasonCtrl = TextEditingController();
  bool _submitting = false;
  String? _errorText;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      setState(() => _errorText = '삭제 사유를 입력해주세요.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    try {
      await ref
          .read(proposalRepositoryProvider)
          .submitDeleteProposal(targetEventId: widget.event.id, reason: reason);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제 제안이 등록되었습니다 (관리자 검토 대기)')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      // 동일 target 에 pending 삭제 제안이 이미 존재하면 partial unique index
      // 위반 (SQLSTATE 23505). 친근한 메시지로 치환.
      final msg = e.code == '23505'
          ? '이미 다른 사역자가 이 이야기의 삭제 제안을 등록했습니다. '
                '관리자 검토가 끝난 뒤에 다시 시도해주세요.'
          : 'DB 오류: ${e.message}';
      setState(() {
        _submitting = false;
        _errorText = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = '제출 실패: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.delete_outline,
                color: theme.colorScheme.error,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '이야기 삭제 제안',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _submitting
                    ? null
                    : () => Navigator.of(context).pop(false),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '대상: "${widget.event.title}"',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '관리자가 승인하면 이 이야기는 앱에서 숨겨집니다. 기존 사용자의 퀴즈 '
            '진도는 보존됩니다. 되돌리고 싶다면 관리자에게 문의해주세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _reasonCtrl,
            minLines: 3,
            maxLines: 6,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '삭제 사유 (필수)',
              hintText: '예: 중복되는 이야기라 이쪽을 제거하고 다른 버전을 유지하는 게 좋겠습니다.',
            ),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: _submitting ? null : _submit,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _submitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('삭제 제안 제출'),
            ),
          ),
        ],
      ),
    );
  }
}
