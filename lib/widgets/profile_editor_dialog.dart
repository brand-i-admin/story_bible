import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_user_profile.dart';
import '../state/auth_providers.dart';
import '../theme/tokens.dart';
import 'story_home_styles.dart';

/// 사용자 프로필(닉네임/사진/기도제목)을 수정하는 모달 다이얼로그.
///
/// 저장에 성공하면 `Navigator.pop`으로 갱신된 [AppUserProfile]을 반환한다.
class ProfileEditorDialog extends ConsumerStatefulWidget {
  const ProfileEditorDialog({
    super.key,
    required this.initialProfile,
    required this.userId,
  });

  final AppUserProfile initialProfile;
  final String userId;

  @override
  ConsumerState<ProfileEditorDialog> createState() =>
      _ProfileEditorDialogState();
}

class _ProfileEditorDialogState extends ConsumerState<ProfileEditorDialog> {
  late final TextEditingController _nicknameController;
  late final TextEditingController _prayerController;
  final ImagePicker _picker = ImagePicker();

  Uint8List? _selectedBytes;
  String? _selectedExtension;
  bool _saving = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _nicknameController = TextEditingController(
      text: widget.initialProfile.nickname,
    );
    _prayerController = TextEditingController(
      text: widget.initialProfile.prayerRequest ?? '',
    );
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    _prayerController.dispose();
    super.dispose();
  }

  Future<void> _pickProfileImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 86,
      );
      if (picked == null || !mounted) {
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedBytes = bytes;
        _selectedExtension = picked.path.split('.').last;
        _localError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localError = '사진을 불러오지 못했습니다.\n$error';
      });
    }
  }

  Future<void> _saveProfile() async {
    final nickname = _nicknameController.text.trim();
    if (nickname.isEmpty) {
      setState(() {
        _localError = '닉네임을 입력해 주세요.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _localError = null;
    });

    try {
      String? nextPhotoUrl = widget.initialProfile.photoUrl;
      if (_selectedBytes != null) {
        nextPhotoUrl = await ref
            .read(userRepositoryProvider)
            .uploadProfileImage(
              userId: widget.userId,
              bytes: _selectedBytes!,
              extension: _selectedExtension ?? 'png',
            );
      }

      final updatedProfile = await ref
          .read(userRepositoryProvider)
          .updateUserProfile(
            userId: widget.userId,
            nickname: nickname,
            prayerRequest: _prayerController.text,
            photoUrl: nextPhotoUrl,
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(updatedProfile);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _localError = '프로필을 저장하지 못했습니다.\n$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _editorSectionLabel(String title, {String? subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.ink500,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null && subtitle.trim().isNotEmpty) ...[
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              subtitle.trim(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink200,
                fontSize: 10.4,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
          ),
        ],
      ],
    );
  }

  InputDecoration _editorInputDecoration({
    required String hintText,
    bool multiLine = false,
  }) {
    const borderColor = Color(0xB88E6F48);
    const focusedBorderColor = Color(0xFFB87731);
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: AppColors.ink150,
        fontSize: 12.4,
        fontWeight: FontWeight.w600,
      ),
      filled: true,
      fillColor: const Color(0xFFF9F2E7),
      isDense: !multiLine,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: multiLine ? 14 : 12,
      ),
      counterText: '',
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor, width: 1.1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: borderColor, width: 1.1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: focusedBorderColor, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0x558E6F48), width: 1.0),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Container(
          decoration: modalSurfaceDecoration(),
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: SingleChildScrollView(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 500;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(context),
                    const SizedBox(height: 14),
                    _buildResponsiveBody(isWide),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          child: Text(
            '프로필 수정',
            style: TextStyle(
              color: Color(0xFF3F2A17),
              fontSize: 26,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        TextButton(
          onPressed: _saving ? null : _saveProfile,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF9B5C1E),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          child: Text(_saving ? '저장 중' : '저장'),
        ),
        const SizedBox(width: 8),
        _CloseButton(
          enabled: !_saving,
          onTap: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildResponsiveBody(bool isWide) {
    final photoCard = _buildPhotoCard();
    final formCard = _buildFormCard();
    if (!isWide) {
      return Column(
        children: [photoCard, const SizedBox(height: 14), formCard],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 156, child: photoCard),
        const SizedBox(width: 14),
        Expanded(child: formCard),
      ],
    );
  }

  Widget _buildPhotoCard() {
    return Container(
      decoration: floatingPanelDecoration(
        color: const Color(0xFFF4E6CF),
        shadowOpacity: 0.06,
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ProfileImagePreview(
            initials: _initials(),
            imageProvider: _imageProvider(),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _pickProfileImage,
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: const Text('사진 바꾸기'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF8A5523),
                side: const BorderSide(color: Color(0xB88E6F48), width: 1.1),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormCard() {
    return Container(
      decoration: floatingPanelDecoration(
        color: const Color(0xFFF6EAD4),
        shadowOpacity: 0.05,
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _editorSectionLabel('닉네임', subtitle: '다른 사람에게 보이는 이름이에요.'),
          const SizedBox(height: 6),
          _NicknameField(
            controller: _nicknameController,
            enabled: !_saving,
            decoration: _editorInputDecoration(hintText: '예: 기도왕, 다윗러버'),
            onChanged: _clearLocalError,
          ),
          const SizedBox(height: 12),
          _editorSectionLabel('기도제목', subtitle: '함께 기도받고 싶은 내용을 짧게 적어보세요.'),
          const SizedBox(height: 6),
          _PrayerField(
            controller: _prayerController,
            enabled: !_saving,
            decoration: _editorInputDecoration(
              hintText: '예: 이번 주에 마음이 지치지 않도록 함께 기도해주세요.',
              multiLine: true,
            ),
            onChanged: _clearLocalError,
          ),
          if (_localError != null) ...[
            const SizedBox(height: 12),
            _ErrorMessageBox(message: _localError!),
          ],
        ],
      ),
    );
  }

  String _initials() {
    final nickname = widget.initialProfile.nickname.trim();
    return nickname.isEmpty ? '?' : nickname.substring(0, 1);
  }

  ImageProvider? _imageProvider() {
    if (_selectedBytes != null) return MemoryImage(_selectedBytes!);
    final photoUrl = (widget.initialProfile.photoUrl ?? '').trim();
    return photoUrl.isEmpty ? null : NetworkImage(photoUrl);
  }

  void _clearLocalError() {
    if (_localError != null) {
      setState(() => _localError = null);
    }
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.enabled, required this.onTap});

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0x90FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xAA8E6F48), width: 1),
          ),
          child: const Icon(
            Icons.close_rounded,
            color: AppColors.ink300,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _ProfileImagePreview extends StatelessWidget {
  const _ProfileImagePreview({
    required this.initials,
    required this.imageProvider,
  });

  final String initials;
  final ImageProvider? imageProvider;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEFD79B), Color(0xFFC88A3D)],
        ),
        border: Border.all(color: const Color(0xFF8C6743), width: 1.8),
      ),
      child: ClipOval(
        child: imageProvider == null
            ? _InitialsFallback(initials: initials)
            : Image(
                image: imageProvider!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _InitialsFallback(initials: initials),
              ),
      ),
    );
  }
}

class _InitialsFallback extends StatelessWidget {
  const _InitialsFallback({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initials,
        style: const TextStyle(
          color: AppColors.ink500,
          fontSize: 28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _NicknameField extends StatelessWidget {
  const _NicknameField({
    required this.controller,
    required this.enabled,
    required this.decoration,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final InputDecoration decoration;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLength: 24,
      textInputAction: TextInputAction.next,
      style: const TextStyle(
        color: AppColors.ink600,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      onChanged: (_) => onChanged(),
      decoration: decoration,
    );
  }
}

class _PrayerField extends StatelessWidget {
  const _PrayerField({
    required this.controller,
    required this.enabled,
    required this.decoration,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final InputDecoration decoration;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLength: 120,
      minLines: 3,
      maxLines: 4,
      style: const TextStyle(
        color: AppColors.ink500,
        fontSize: 12.8,
        fontWeight: FontWeight.w700,
        height: 1.45,
      ),
      onChanged: (_) => onChanged(),
      decoration: decoration,
    );
  }
}

class _ErrorMessageBox extends StatelessWidget {
  const _ErrorMessageBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x14A63F2D),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x55A63F2D), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF8E3626),
          fontSize: 11,
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
    );
  }
}
