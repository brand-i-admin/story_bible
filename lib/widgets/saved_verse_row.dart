import 'package:flutter/material.dart';

import '../models/saved_bible_verse.dart';
import '../theme/tokens.dart';
import '../utils/bible_book_meta.dart';

class SavedVerseRow extends StatelessWidget {
  const SavedVerseRow({
    super.key,
    required this.verse,
    this.onTap,
    this.onDelete,
    this.compact = false,
  });

  final SavedBibleVerse verse;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final badgeSize = compact ? 28.0 : 32.0;
    final comment = verse.comment.trim();
    final showComment = verse.isSaved;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          key: const ValueKey('saved-verse-row-container'),
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.fromLTRB(
            compact ? 8 : 10,
            compact ? 8 : 10,
            onDelete == null ? (compact ? 8 : 10) : 4,
            compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: _savedVerseRowBackground(verse),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderHairlineDark, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SavedVerseReferenceBadge(
                          verse: verse,
                          size: badgeSize,
                        ),
                        SizedBox(width: compact ? 7 : 8),
                        Expanded(
                          child: Text(
                            verse.verseText,
                            style: TextStyle(
                              color: AppColors.ink800,
                              fontSize: compact ? 12.1 : 13.4,
                              height: 1.42,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showComment) ...[
                      SizedBox(height: compact ? 7 : 9),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: AppColors.borderHairlineDark.withAlpha(110),
                      ),
                      SizedBox(height: compact ? 7 : 8),
                      Text(
                        comment.isEmpty ? '남긴 코멘트가 없습니다.' : comment,
                        style: TextStyle(
                          color: comment.isEmpty
                              ? AppColors.ink150
                              : AppColors.ink500,
                          fontSize: compact ? 11.5 : 12.7,
                          height: 1.42,
                          fontWeight: comment.isEmpty
                              ? FontWeight.w700
                              : FontWeight.w800,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (onDelete != null) ...[
                SizedBox(width: compact ? 4 : 6),
                SizedBox(
                  width: compact ? 34 : 38,
                  child: IconButton(
                    tooltip: verse.isSaved ? '저장 취소' : '하이라이트 삭제',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: AppColors.seed,
                    splashRadius: 18,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Color _savedVerseRowBackground(SavedBibleVerse verse) {
  return switch (verse.highlightColor) {
    SavedBibleVerse.highlightBlue => const Color(0x6639C6E8),
    SavedBibleVerse.highlightYellow => const Color(0x66FFF176),
    _ => AppColors.gold.withAlpha(34),
  };
}

class _SavedVerseReferenceBadge extends StatelessWidget {
  const _SavedVerseReferenceBadge({required this.verse, required this.size});

  final SavedBibleVerse verse;
  final double size;

  @override
  Widget build(BuildContext context) {
    final alias = bibleBookNoToAlias[verse.bookNo] ?? verse.bookName;

    return Container(
      key: const ValueKey('saved-verse-reference-badge'),
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.greenTop, AppColors.greenBot],
        ),
        border: Border.all(color: const Color(0xFFF6EEDC), width: 1.7),
        boxShadow: const [
          BoxShadow(
            color: Color(0x24000000),
            blurRadius: 8,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(size < 30 ? 4.2 : 4.8),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                alias,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size < 30 ? 8.7 : 9.3,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              SizedBox(height: size < 30 ? 1 : 1.5),
              Text(
                '${verse.chapterNo}:${verse.verseNo}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size < 30 ? 8.6 : 9.2,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
