import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../widgets/game_ui_skin.dart';
import '../../../data/models/bible_event_model.dart';

class DetailTitleRow extends StatelessWidget {
  const DetailTitleRow({
    super.key,
    required this.event,
    required this.canMovePrev,
    required this.canMoveNext,
    required this.onMovePrev,
    required this.onMoveNext,
  });

  final BibleEvent event;
  final bool canMovePrev;
  final bool canMoveNext;
  final VoidCallback onMovePrev;
  final VoidCallback onMoveNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                event.title,
                style: GoogleFonts.nanumMyeongjo(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                event.verseRef,
                style: GoogleFonts.notoSerifKr(
                  fontSize: 11,
                  color: AppColors.red,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          children: [
            _navButton('‹ 이전', canMovePrev, onMovePrev),
            const SizedBox(width: 5),
            _navButton('다음 ›', canMoveNext, onMoveNext),
          ],
        ),
      ],
    );
  }

  Widget _navButton(String text, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: SizedBox(
          width: 74,
          height: 30,
          child: DecoratedBox(
            decoration: actionButtonDecoration(selected: enabled),
            child: Center(
              child: Text(
                text,
                style: GoogleFonts.notoSerifKr(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFDF8EE),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
