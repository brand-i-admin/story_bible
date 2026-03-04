import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../widgets/game_ui_skin.dart';

class ProgressStrip extends StatelessWidget {
  const ProgressStrip({
    super.key,
    required this.total,
    required this.completed,
    required this.currentIndex,
    required this.onDotTap,
    required this.isDone,
  });

  final int total;
  final int completed;
  final int currentIndex;
  final ValueChanged<int> onDotTap;
  final bool Function(int) isDone;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : completed / total;
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: panelLabelBackdropDecoration().copyWith(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '진행도',
                style: GoogleFonts.notoSerifKr(
                  fontSize: 9,
                  color: AppColors.goldDim.withValues(alpha: 0.64),
                ),
              ),
              const Spacer(),
              Text(
                '$completed / $total 완료',
                style: GoogleFonts.nanumMyeongjo(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.gold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 4,
              child: Stack(
                children: [
                  Container(color: AppColors.goldDim.withValues(alpha: 0.16)),
                  FractionallySizedBox(
                    widthFactor: ratio,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFFC9942A), AppColors.gold],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(total, (index) {
              final done = isDone(index);
              final isCurrent = currentIndex == index;
              return InkWell(
                onTap: () => onDotTap(index),
                child: Container(
                  width: 17,
                  height: 17,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: done
                        ? const LinearGradient(
                            colors: [
                              AppColors.greenDone,
                              AppColors.greenBright,
                            ],
                          )
                        : null,
                    color: done
                        ? null
                        : isCurrent
                        ? const Color(0x30C9942A)
                        : const Color(0x14A07846),
                    border: Border.all(
                      width: 1.5,
                      color: done
                          ? AppColors.greenDone
                          : isCurrent
                          ? const Color(0xFFC9942A)
                          : const Color(0x4DA07846),
                    ),
                  ),
                  child: done
                      ? Image.asset(kCheckBoxAsset, fit: BoxFit.contain)
                      : Text(
                          '${index + 1}',
                          style: GoogleFonts.notoSerifKr(
                            fontSize: 7,
                            color: isCurrent
                                ? AppColors.gold
                                : AppColors.inkMid.withValues(alpha: 0.45),
                          ),
                        ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
