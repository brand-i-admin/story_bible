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
    final badgeSize = compact ? 42.0 : 48.0;
    final textMaxLines = compact ? 2 : 3;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.fromLTRB(
            compact ? 6 : 8,
            compact ? 7 : 9,
            onDelete == null ? (compact ? 8 : 10) : 2,
            compact ? 7 : 9,
          ),
          decoration: BoxDecoration(
            color: AppColors.gold.withAlpha(34),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderHairlineDark, width: 1),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _SavedVerseReferenceBadge(verse: verse, size: badgeSize),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Text(
                  verse.verseText,
                  maxLines: textMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.ink800,
                    fontSize: compact ? 12.2 : 13.6,
                    height: 1.42,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (onDelete != null) ...[
                SizedBox(width: compact ? 2 : 4),
                IconButton(
                  tooltip: '삭제',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.seed,
                  splashRadius: 18,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
        padding: EdgeInsets.all(size < 46 ? 5.5 : 6),
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
                  fontSize: size < 46 ? 10.5 : 11,
                  fontWeight: FontWeight.w900,
                  height: 1.0,
                ),
              ),
              SizedBox(height: size < 46 ? 1.5 : 2),
              Text(
                '${verse.chapterNo}:${verse.verseNo}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size < 46 ? 10.5 : 11,
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
