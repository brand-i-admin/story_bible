import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'parchment_dialog.dart';

/// 7자리 공유 ID를 입력받는 다이얼로그.
///
/// 중보기도 추가 시 상대방의 [share_id]를 입력받는다.
/// 닫을 때 `pop(result)`로 공유 ID 문자열(또는 null)을 반환한다.
class ShareIdInputDialog extends StatefulWidget {
  const ShareIdInputDialog({super.key});

  @override
  State<ShareIdInputDialog> createState() => _ShareIdInputDialogState();
}

class _ShareIdInputDialogState extends State<ShareIdInputDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode();
    _controller.addListener(_normalizeText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_normalizeText);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _normalizeText() {
    final normalized = _controller.text.toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    if (_controller.text == normalized) {
      return;
    }
    _controller.value = _controller.value.copyWith(
      text: normalized,
      selection: TextSelection.collapsed(offset: normalized.length),
      composing: TextRange.empty,
    );
  }

  void _close([String? result]) {
    FocusManager.instance.primaryFocus?.unfocus();
    _focusNode.unfocus();
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) {
        final shareId = value.text.trim().toUpperCase();
        final canSubmit = shareId.length == 7;

        return ParchmentDialog(
          title: '공유 ID 추가',
          maxWidth: 410,
          showCloseButton: true,
          onClose: _close,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ParchmentDialogTextField(
                controller: _controller,
                focusNode: _focusNode,
                hintText: '예: A1B2C3D',
                maxLength: 7,
                textCapitalization: TextCapitalization.characters,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                ],
                onSubmitted: canSubmit ? (_) => _close(shareId) : null,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ParchmentDialogActionButton(
                  label: '추가',
                  onTap: canSubmit ? () => _close(shareId) : null,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
