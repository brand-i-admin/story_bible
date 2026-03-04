import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../data/models/bible_event_model.dart';

class EventList extends StatelessWidget {
  const EventList({
    super.key,
    required this.events,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<BibleEvent> events;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    if (events.isEmpty) {
      return Expanded(
        child: Center(
          child: Text(
            '사건 데이터가 없습니다',
            style: GoogleFonts.notoSerifKr(
              fontSize: isPhone ? 12 : 11,
              color: const Color(0xFFF2DFC0),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
        itemCount: events.length,
        itemBuilder: (context, index) {
          final event = events[index];
          final previousSection = index == 0 ? null : events[index - 1].section;
          final showSection = event.section != previousSection;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showSection) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 9, 12, 3),
                  child: Text(
                    event.section,
                    style: GoogleFonts.notoSerifKr(
                      fontSize: isPhone ? 9.6 : 8.8,
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.w700,
                      color: AppColors.goldDim.withValues(alpha: 0.82),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  height: 1,
                  color: AppColors.goldDim.withValues(alpha: 0.22),
                ),
              ],
              _EventListItem(
                event: event,
                active: index == selectedIndex,
                onTap: () => onSelect(index),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EventListItem extends StatelessWidget {
  const _EventListItem({
    required this.event,
    required this.active,
    required this.onTap,
  });

  final BibleEvent event;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isPhone = MediaQuery.of(context).size.shortestSide < 600;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
        constraints: BoxConstraints(minHeight: isPhone ? 60 : 54),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.woodLight, AppColors.woodMid],
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 5,
              offset: Offset(0, 1.5),
            ),
          ],
        ),
        child: Container(
          margin: const EdgeInsets.all(1.6),
          padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF5EDD5), AppColors.parchMid],
            ),
            border: Border.all(
              color: active ? const Color(0x99C9942A) : const Color(0x409B7444),
              width: active ? 1.1 : 0.8,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            event.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.notoSerifKr(
                              fontSize: isPhone ? 12.2 : 11.4,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        if (event.isCompleted)
                          Container(
                            width: 15,
                            height: 15,
                            margin: const EdgeInsets.only(left: 6, top: 1),
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                colors: [
                                  AppColors.greenDone,
                                  AppColors.greenBright,
                                ],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const Text(
                              '✓',
                              style: TextStyle(
                                fontSize: 7.2,
                                color: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          event.verseRef,
                          style: GoogleFonts.notoSerifKr(
                            fontSize: isPhone ? 9.8 : 9.2,
                            fontWeight: FontWeight.w700,
                            color: AppColors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      event.snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.notoSerifKr(
                        fontSize: isPhone ? 9.8 : 9.2,
                        color: AppColors.inkMid.withValues(alpha: 0.88),
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
