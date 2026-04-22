import 'package:flutter/material.dart';

import '../models/character.dart';

/// 인물 아바타 (원형, 동그란 테두리 + 그림자).
///
/// 주간 탭, 프로필 탭 등 여러 곳에서 공용으로 사용된다.
/// 이미지 로드 실패 시 이름의 첫 글자를 표시하는 fallback이 렌더링된다.
class CharacterAvatar extends StatelessWidget {
  const CharacterAvatar({super.key, required this.character, this.size = 32});

  final Character character;
  final double size;

  @override
  Widget build(BuildContext context) {
    final avatarPath = character.avatarAssetPath.trim();
    final fallbackText = character.name.trim().isEmpty
        ? '?'
        : character.name.trim().substring(0, 1);
    final borderWidth = (size * 0.045).clamp(1.0, 1.6).toDouble();
    final fallbackFontSize = (size * 0.34).clamp(9.0, 11.5).toDouble();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFF3E7CC), width: borderWidth),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 2),
        ],
      ),
      child: ClipOval(
        child: avatarPath.isEmpty
            ? _Fallback(text: fallbackText, fontSize: fallbackFontSize)
            : ColoredBox(
                color: Colors.white,
                child: FittedBox(
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                    width: size,
                    height: size * 2,
                    child: Image.asset(
                      avatarPath,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) => _Fallback(
                        text: fallbackText,
                        fontSize: fallbackFontSize,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.text, this.fontSize = 11});

  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF8C6337),
      alignment: Alignment.center,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: const Color(0xFFF3EAD6),
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
