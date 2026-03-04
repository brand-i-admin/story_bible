import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../shared/widgets/wood_frame.dart';
import '../../../../../widgets/game_ui_skin.dart';
import '../../../data/models/verse_page_model.dart';

class VerseFullBox extends StatelessWidget {
  const VerseFullBox({
    super.key,
    required this.pages,
    required this.currentPage,
    required this.onPrev,
    required this.onNext,
    this.onOpenFullscreen,
  });

  final List<VersePage> pages;
  final int currentPage;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback? onOpenFullscreen;

  @override
  Widget build(BuildContext context) {
    if (pages.isEmpty) {
      return const SizedBox.shrink();
    }
    final safePageIndex = currentPage.clamp(0, pages.length - 1);
    final page = pages[safePageIndex];
    final canPrev = safePageIndex > 0;
    final canNext = safePageIndex < pages.length - 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: WoodFrame(
        innerPadding: EdgeInsets.zero,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: const BoxDecoration(
                color: Color(0xD92C1F0E),
                borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '📜 본문 구절',
                              style: GoogleFonts.notoSerifKr(
                                fontSize: 9,
                                letterSpacing: 0.8,
                                color: AppColors.goldDim.withValues(
                                  alpha: 0.85,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              page.ref,
                              style: GoogleFonts.nanumMyeongjo(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: AppColors.gold,
                              ),
                            ),
                            if (onOpenFullscreen != null) ...[
                              const SizedBox(width: 7),
                              InkWell(
                                onTap: onOpenFullscreen,
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.goldDim.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                  ),
                                  child: Text(
                                    '전체',
                                    style: GoogleFonts.notoSerifKr(
                                      fontSize: 8,
                                      color: AppColors.gold,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onOpenFullscreen,
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 58),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF5EDD5), Color(0xFFECDEBA)],
                  ),
                ),
                child: Text(
                  page.text,
                  style: GoogleFonts.notoSerifKr(
                    fontSize: 11,
                    height: 1.8,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFECDEBA), AppColors.parchMid],
                ),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(6)),
              ),
              child: Row(
                children: [
                  _pageButton('◀ 앞 구절', canPrev, onPrev),
                  const Spacer(),
                  Text(
                    '${safePageIndex + 1} / ${pages.length}',
                    style: GoogleFonts.notoSerifKr(
                      fontSize: 10,
                      color: AppColors.inkLight,
                    ),
                  ),
                  const Spacer(),
                  _pageButton('뒷 구절 ▶', canNext, onNext),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pageButton(String text, bool enabled, VoidCallback onTap) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(7),
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: SizedBox(
          width: 76,
          height: 26,
          child: DecoratedBox(
            decoration: actionButtonDecoration(selected: enabled),
            child: Center(
              child: Text(
                text,
                style: GoogleFonts.notoSerifKr(
                  fontSize: 8.5,
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
