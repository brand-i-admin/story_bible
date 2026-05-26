import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/saved_bible_verse.dart';
import '../state/auth_providers.dart';
import '../theme/tokens.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/parchment_page_scaffold.dart';
import '../widgets/saved_verse_row.dart';

class SavedVersesScreen extends ConsumerStatefulWidget {
  const SavedVersesScreen({super.key, this.onOpenVerse});

  final Future<void> Function(SavedBibleVerse verse)? onOpenVerse;

  @override
  ConsumerState<SavedVersesScreen> createState() => _SavedVersesScreenState();
}

class _SavedVersesScreenState extends ConsumerState<SavedVersesScreen> {
  static const _pageSize = 10;

  int _pageIndex = 0;
  bool _loading = true;
  bool _hasNextPage = false;
  String? _error;
  List<SavedBibleVerse> _verses = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadVerses);
  }

  Future<void> _loadVerses() async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      setState(() {
        _loading = false;
        _error = '로그인 정보를 찾을 수 없습니다.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ref
          .read(userRepositoryProvider)
          .fetchSavedVersesPage(
            userId: user.id,
            pageIndex: _pageIndex,
            pageSize: _pageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _verses = result.items;
        _hasNextPage = result.hasNextPage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '저장한 말씀을 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<void> _deleteVerse(SavedBibleVerse verse) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ParchmentDialog(
        title: '말씀 저장을 삭제할까요?',
        subtitle: '정말 지우시겠습니까?',
        actions: [
          ParchmentDialogActionButton(
            label: '취소',
            style: ParchmentDialogActionStyle.secondary,
            onTap: () => Navigator.of(dialogContext).pop(false),
          ),
          ParchmentDialogActionButton(
            label: '삭제',
            style: ParchmentDialogActionStyle.danger,
            onTap: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
        child: const SizedBox.shrink(),
      ),
    );

    if (confirmed != true) {
      return;
    }

    try {
      await ref.read(userRepositoryProvider).deleteSavedVerse(verse.id);
      if (!mounted) {
        return;
      }
      if (_verses.length == 1 && _pageIndex > 0) {
        setState(() {
          _pageIndex -= 1;
        });
      }
      await _loadVerses();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장이 삭제되었어요.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('삭제하지 못했습니다.\n$error')));
    }
  }

  Future<void> _openVerse(SavedBibleVerse verse) async {
    final onOpenVerse = widget.onOpenVerse;
    if (onOpenVerse == null) {
      return;
    }
    try {
      await onOpenVerse(verse);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('말씀 위치로 이동하지 못했습니다.\n$error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ParchmentPageScaffold(
      title: '저장한 말씀',
      compactBackOnly: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
        child: Column(
          children: [
            Expanded(
              child: ParchmentCard(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: Column(
                  children: [
                    Expanded(child: _buildBody()),
                    if (!_loading && _error == null && _verses.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildPagination(),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFFA63F2D),
            fontWeight: FontWeight.w800,
            height: 1.5,
          ),
        ),
      );
    }
    if (_verses.isEmpty) {
      return const Center(
        child: Text(
          '아직 저장한 말씀이 없습니다.\n성경 화면에서 구절을 눌러 저장해 보세요.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF6D5231),
            fontWeight: FontWeight.w700,
            height: 1.6,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: _verses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final verse = _verses[index];
        return SavedVerseRow(
          verse: verse,
          onTap: widget.onOpenVerse == null ? null : () => _openVerse(verse),
          onDelete: () => _deleteVerse(verse),
        );
      },
    );
  }

  Widget _buildPagination() {
    final visiblePages = List<int>.generate(
      _pageIndex + (_hasNextPage ? 2 : 1),
      (index) => index,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _PageArrowButton(
          onPressed: _pageIndex == 0
              ? null
              : () async {
                  setState(() {
                    _pageIndex -= 1;
                  });
                  await _loadVerses();
                },
          label: '<',
        ),
        const SizedBox(width: 6),
        ...visiblePages.map((page) {
          final selected = page == _pageIndex;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: selected
                  ? null
                  : () async {
                      setState(() {
                        _pageIndex = page;
                      });
                      await _loadVerses();
                    },
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected
                      ? const Color(0xFFE0B25B)
                      : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? const Color(0xFFB7742B)
                        : const Color(0x558E6F48),
                  ),
                ),
                child: Text(
                  '${page + 1}',
                  style: TextStyle(
                    color: selected
                        ? AppColors.ink500
                        : const Color(0xFF7B603D),
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          );
        }),
        const SizedBox(width: 6),
        _PageArrowButton(
          onPressed: !_hasNextPage
              ? null
              : () async {
                  setState(() {
                    _pageIndex += 1;
                  });
                  await _loadVerses();
                },
          label: '>',
        ),
      ],
    );
  }
}

class _PageArrowButton extends StatelessWidget {
  const _PageArrowButton({required this.onPressed, required this.label});

  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: enabled ? const Color(0xAA8E6F48) : const Color(0x338E6F48),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? AppColors.ink500 : const Color(0x557B603D),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
