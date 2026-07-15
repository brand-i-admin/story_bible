import 'package:flutter/material.dart';

import 'parchment_dialog.dart';

Future<void> showLoginRequiredDialog({
  required BuildContext context,
  required String message,
  required VoidCallback onOpenMyInfo,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => ParchmentDialog(
      title: '로그인이 필요해요',
      subtitle: message,
      actions: [
        ParchmentDialogActionButton(
          label: '취소',
          style: ParchmentDialogActionStyle.secondary,
          onTap: () => Navigator.of(dialogContext).pop(),
        ),
        ParchmentDialogActionButton(
          label: '내정보로 이동',
          onTap: () {
            Navigator.of(dialogContext).pop();
            onOpenMyInfo();
          },
        ),
      ],
      child: const Text('내정보 화면에서 로그인한 뒤 다시 이용해 주세요.'),
    ),
  );
}
