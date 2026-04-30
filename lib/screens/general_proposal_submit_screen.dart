import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../state/auth_providers.dart';
import '../state/proposal_providers.dart';

/// 앱 전반에 대한 자유 제안(`proposal_type='general'`) 작성 화면.
///
/// 제목 + 본문 텍스트 필수, 첨부 이미지 최대 5장. 제출 시:
///   1. 선택된 이미지를 `proposal-general-images/<uid>/<draft>/<idx>.<ext>`
///      로 차례대로 업로드
///   2. `submit_general_proposal` RPC 호출
///   3. 성공하면 게시판으로 복귀.
class GeneralProposalSubmitScreen extends ConsumerStatefulWidget {
  const GeneralProposalSubmitScreen({super.key});

  @override
  ConsumerState<GeneralProposalSubmitScreen> createState() =>
      _GeneralProposalSubmitScreenState();
}

class _GeneralProposalSubmitScreenState
    extends ConsumerState<GeneralProposalSubmitScreen> {
  static const _maxImages = 5;

  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _picker = ImagePicker();
  final List<_PickedImage> _images = [];
  late final String _draftId;

  bool _submitting = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _draftId = _generateDraftId();
    _titleCtrl.addListener(_onChanged);
    _bodyCtrl.addListener(_onChanged);
  }

  @override
  void dispose() {
    _titleCtrl.removeListener(_onChanged);
    _bodyCtrl.removeListener(_onChanged);
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  String _generateDraftId() {
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    final rand = (DateTime.now().microsecondsSinceEpoch & 0xffff).toRadixString(
      16,
    );
    return 'draft_${ts}_$rand';
  }

  bool get _canSubmit =>
      !_submitting &&
      _titleCtrl.text.trim().isNotEmpty &&
      _bodyCtrl.text.trim().isNotEmpty;

  Future<void> _pickImage() async {
    if (_images.length >= _maxImages) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 88,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      final extension = _extractExtension(picked.path);
      if (!mounted) return;
      setState(() {
        _images.add(_PickedImage(bytes: bytes, extension: extension));
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = '이미지를 불러오지 못했습니다: $e');
    }
  }

  String _extractExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'png';
    return path.substring(dot + 1);
  }

  void _removeImage(int index) {
    setState(() {
      _images.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      setState(() => _errorText = '로그인이 필요합니다.');
      return;
    }
    setState(() {
      _submitting = true;
      _errorText = null;
    });
    final repo = ref.read(proposalRepositoryProvider);
    try {
      final paths = <String>[];
      for (var i = 0; i < _images.length; i++) {
        final img = _images[i];
        final path = await repo.uploadGeneralProposalImage(
          userId: user.id,
          draftId: _draftId,
          index: i,
          bytes: img.bytes,
          extension: img.extension,
        );
        paths.add(path);
      }
      await repo.submitGeneralProposal(
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        imagePaths: paths,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일반 제안이 등록되었습니다 (관리자 검토 대기)')),
      );
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorText = 'DB 오류: ${e.message}';
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
    final canAddMore = _images.length < _maxImages && !_submitting;
    return Scaffold(
      appBar: AppBar(
        title: const Text('새 일반 제안'),
        actions: [
          TextButton(
            onPressed: _canSubmit ? _submit : null,
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('등록'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            if (_errorText != null) ...[
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    _errorText!,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _titleCtrl,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예: 인물 검색에 별명도 포함되면 좋겠어요',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyCtrl,
              minLines: 6,
              maxLines: 14,
              decoration: const InputDecoration(
                labelText: '내용',
                hintText: '제안하고 싶은 내용을 자유롭게 작성해주세요. 캡처/사진은 아래에서 첨부할 수 있어요.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(
                  '첨부 이미지',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_images.length}/$_maxImages',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _ImageThumbStrip(
              images: _images,
              onRemove: _submitting ? null : _removeImage,
              onAdd: canAddMore ? _pickImage : null,
            ),
            const SizedBox(height: 16),
            Text(
              '관리자가 승인/거절한 후에도 이미지는 자동으로 삭제되지 않습니다 (필요 시 관리자가 수동 정리).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PickedImage {
  const _PickedImage({required this.bytes, required this.extension});
  final Uint8List bytes;
  final String extension;
}

class _ImageThumbStrip extends StatelessWidget {
  const _ImageThumbStrip({
    required this.images,
    required this.onRemove,
    required this.onAdd,
  });

  final List<_PickedImage> images;
  final void Function(int index)? onRemove;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length + (onAdd != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, idx) {
          if (idx == images.length) {
            return _AddImageTile(onTap: onAdd);
          }
          return _ImageThumb(
            image: images[idx],
            onRemove: onRemove == null ? null : () => onRemove!(idx),
            theme: theme,
          );
        },
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({
    required this.image,
    required this.onRemove,
    required this.theme,
  });

  final _PickedImage image;
  final VoidCallback? onRemove;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Image.memory(image.bytes, fit: BoxFit.cover),
          ),
        ),
        if (onRemove != null)
          Positioned(
            top: 4,
            right: 4,
            child: Material(
              color: Colors.black.withValues(alpha: 0.55),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: Colors.white),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AddImageTile extends StatelessWidget {
  const _AddImageTile({required this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final disabled = onTap == null;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          border: Border.all(
            color: disabled
                ? theme.colorScheme.outlineVariant
                : theme.colorScheme.primary.withValues(alpha: 0.7),
            style: BorderStyle.solid,
            width: 1.4,
          ),
          borderRadius: BorderRadius.circular(10),
          color: disabled
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.primary.withValues(alpha: 0.06),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_a_photo_outlined,
              color: disabled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.primary,
            ),
            const SizedBox(height: 6),
            Text(
              '사진 추가',
              style: theme.textTheme.labelSmall?.copyWith(
                color: disabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
