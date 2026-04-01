import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/user_note.dart';
import '../state/auth_providers.dart';
import '../widgets/parchment_dialog.dart';
import '../widgets/parchment_page_scaffold.dart';
import 'profile_note_editor_screen.dart';

class ProfileNotesScreen extends ConsumerStatefulWidget {
  const ProfileNotesScreen({super.key});

  @override
  ConsumerState<ProfileNotesScreen> createState() => _ProfileNotesScreenState();
}

class _ProfileNotesScreenState extends ConsumerState<ProfileNotesScreen> {
  static const _pageSize = 10;
  static const _fabDiameter = 54.0;

  int _pageIndex = 0;
  bool _loading = true;
  bool _hasNextPage = false;
  String? _error;
  List<UserNote> _notes = const [];
  Offset? _fabOffset;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadNotes);
  }

  Future<void> _loadNotes({bool showLoading = true}) async {
    final user = ref.read(signedInUserProvider);
    if (user == null) {
      setState(() {
        _loading = false;
        _error = '로그인 정보를 찾을 수 없습니다.';
      });
      return;
    }

    if (showLoading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() {
        _error = null;
      });
    }

    try {
      final result = await ref
          .read(userRepositoryProvider)
          .fetchUserNotesPage(
            userId: user.id,
            pageIndex: _pageIndex,
            pageSize: _pageSize,
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = result.items;
        _hasNextPage = result.hasNextPage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '노트를 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<void> _openComposer() async {
    final payload = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute<Map<String, String>>(
        builder: (_) => const ProfileNoteEditorScreen(),
      ),
    );
    if (!mounted || payload == null) {
      return;
    }

    final user = ref.read(signedInUserProvider);
    if (user == null) {
      return;
    }

    try {
      await ref
          .read(userRepositoryProvider)
          .createUserNote(
            userId: user.id,
            title: payload['title'] ?? '',
            content: payload['content'] ?? '',
          );
      if (!mounted) {
        return;
      }
      setState(() {
        _pageIndex = 0;
      });
      await _loadNotes();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('노트가 저장되었어요.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('노트를 저장하지 못했습니다.\n$error')));
    }
  }

  Future<void> _confirmDeleteNote(UserNote note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ParchmentDialog(
        title: '노트를 삭제할까요?',
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
      await ref.read(userRepositoryProvider).deleteUserNote(note.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _notes = _notes
            .where((entry) => entry.id != note.id)
            .toList(growable: false);
        if (_notes.isEmpty && _pageIndex > 0) {
          _pageIndex -= 1;
        }
      });
      await _loadNotes(showLoading: false);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('노트가 삭제되었어요.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('노트를 삭제하지 못했습니다.\n$error')));
    }
  }

  void _openNoteDetail(UserNote note) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => ParchmentDialog(
        title: note.title,
        subtitle: _formatDateTime(note.createdAt),
        showCloseButton: true,
        actions: [
          ParchmentDialogActionButton(
            label: '닫기',
            style: ParchmentDialogActionStyle.secondary,
            onTap: () => Navigator.of(dialogContext).pop(),
          ),
        ],
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: SingleChildScrollView(
            child: Text(
              note.content,
              style: const TextStyle(
                color: Color(0xFF3E2B18),
                fontSize: 13.2,
                fontWeight: FontWeight.w700,
                height: 1.55,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ParchmentPageScaffold(
      title: '내 노트',
      compactBackOnly: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxFabX = (constraints.maxWidth - _fabDiameter).clamp(
            0.0,
            double.infinity,
          );
          final maxFabY = (constraints.maxHeight - _fabDiameter).clamp(
            0.0,
            double.infinity,
          );
          final fabOffset = Offset(
            (_fabOffset?.dx ?? maxFabX - 2).clamp(0.0, maxFabX).toDouble(),
            (_fabOffset?.dy ?? maxFabY - 4).clamp(0.0, maxFabY).toDouble(),
          );

          return Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(2, 0, 2, 2),
                  child: ParchmentCard(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                    child: Column(
                      children: [
                        Expanded(child: _buildBody()),
                        if (!_loading &&
                            _error == null &&
                            _notes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _buildPagination(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: fabOffset.dx,
                top: fabOffset.dy,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _fabOffset = Offset(
                        (fabOffset.dx + details.delta.dx)
                            .clamp(0.0, maxFabX)
                            .toDouble(),
                        (fabOffset.dy + details.delta.dy)
                            .clamp(0.0, maxFabY)
                            .toDouble(),
                      );
                    });
                  },
                  child: _ProfileNotesFab(onTap: _openComposer),
                ),
              ),
            ],
          );
        },
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
    if (_notes.isEmpty) {
      return const Center(
        child: Text(
          '아직 작성한 노트가 없습니다.\n첫 노트를 남겨 보세요.',
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
      itemCount: _notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final note = _notes[index];
        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _openNoteDetail(note),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
              decoration: BoxDecoration(
                color: const Color(0x66FFFFFF),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xAA8E6F48), width: 1),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                note.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFF4A331D),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatListDate(note.createdAt),
                              style: const TextStyle(
                                color: Color(0xFF8A6A46),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          note.previewLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF6D5231),
                            fontSize: 11.8,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '삭제',
                    onPressed: () => _confirmDeleteNote(note),
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: const Color(0xFF8C5E2B),
                    splashRadius: 18,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),
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
                  await _loadNotes();
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
                      await _loadNotes();
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
                        ? const Color(0xFF4A331D)
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
                  await _loadNotes();
                },
          label: '>',
        ),
      ],
    );
  }

  String _formatListDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$month.$day';
  }

  String _formatDateTime(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.year}.$month.$day $hour:$minute';
  }
}

class _ProfileNotesFab extends StatelessWidget {
  const _ProfileNotesFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Ink(
          width: _ProfileNotesScreenState._fabDiameter,
          height: _ProfileNotesScreenState._fabDiameter,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Color(0xFFCC862F),
            boxShadow: [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.add_rounded,
            size: 30,
            color: Color(0xFFFDF8EE),
          ),
        ),
      ),
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
            color: enabled ? const Color(0xFF4A331D) : const Color(0x557B603D),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}
