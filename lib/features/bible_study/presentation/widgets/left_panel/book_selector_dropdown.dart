import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../core/theme/app_colors.dart';
import '../../../../../widgets/game_ui_skin.dart';
import '../../../data/models/book_model.dart';

class BookSelectorDropdown extends StatefulWidget {
  const BookSelectorDropdown({
    super.key,
    required this.books,
    required this.selectedBook,
    required this.onBookSelected,
  });

  final List<Book> books;
  final Book? selectedBook;
  final ValueChanged<Book> onBookSelected;

  @override
  State<BookSelectorDropdown> createState() => _BookSelectorDropdownState();
}

class _BookSelectorDropdownState extends State<BookSelectorDropdown> {
  bool _expanded = false;

  @override
  void didUpdateWidget(covariant BookSelectorDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When testament changes, close the expanded grid to avoid stale/open state.
    if (_expanded && oldWidget.books != widget.books) {
      _expanded = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      decoration: panelLabelBackdropDecoration().copyWith(
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '성경 선택',
                          style: GoogleFonts.notoSerifKr(
                            fontSize: 9,
                            letterSpacing: 1.2,
                            color: AppColors.goldDim.withValues(alpha: 0.65),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.selectedBook?.name ?? '-',
                          style: GoogleFonts.nanumMyeongjo(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFF5E4A8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Text(
                      '▾',
                      style: GoogleFonts.notoSerifKr(
                        fontSize: 10,
                        color: AppColors.goldDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              heightFactor: _expanded ? 1 : 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 172),
                  child: Scrollbar(
                    child: GridView.builder(
                      primary: false,
                      itemCount: widget.books.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisExtent: 28,
                            crossAxisSpacing: 4,
                            mainAxisSpacing: 4,
                          ),
                      itemBuilder: (context, index) {
                        final book = widget.books[index];
                        final active = book.id == widget.selectedBook?.id;
                        return InkWell(
                          onTap: () {
                            widget.onBookSelected(book);
                            setState(() => _expanded = false);
                          },
                          child: Container(
                            alignment: Alignment.center,
                            decoration: active
                                ? actionButtonDecoration(selected: true)
                                : panelLabelBackdropDecoration().copyWith(
                                    borderRadius: BorderRadius.circular(6),
                                    color: const Color(0x7A2D1B0D),
                                  ),
                            child: Text(
                              book.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.notoSerifKr(
                                fontSize: 10,
                                color: active
                                    ? const Color(0xFFF5E4A8)
                                    : AppColors.goldDim.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
