import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../widgets/game_ui_skin.dart';

class TestamentToggle extends StatelessWidget {
  const TestamentToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 10, 10, 0),
      child: Row(
        children: [
          Expanded(child: _button('구약', 'OT', value == 'OT')),
          const SizedBox(width: 5),
          Expanded(child: _button('신약', 'NT', value == 'NT')),
        ],
      ),
    );
  }

  Widget _button(String label, String testament, bool active) {
    return InkWell(
      onTap: () => onChanged(testament),
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: 32,
        child: DecoratedBox(
          decoration: actionButtonDecoration(selected: active),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.notoSerifKr(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: active ? const Color(0xFFFDF8EE) : AppColors.goldDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
