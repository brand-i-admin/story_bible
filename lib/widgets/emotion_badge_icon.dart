import 'package:flutter/material.dart';

class EmotionBadgeIcon extends StatelessWidget {
  const EmotionBadgeIcon({
    super.key,
    required this.emotionKey,
    this.size = 18,
    this.iconSize,
    this.backgroundColor,
    this.borderColor,
    this.elevation = true,
  });

  final String emotionKey;
  final double size;
  final double? iconSize;
  final Color? backgroundColor;
  final Color? borderColor;
  final bool elevation;

  static String emojiFor(String emotionKey) {
    switch (emotionKey) {
      case 'joy':
        return '🌟';
      case 'anticipation':
        return '🌅';
      case 'gratitude':
        return '💛';
      case 'wonder':
        return '😮';
      case 'sadness':
        return '💧';
      case 'comfort':
        return '🌿';
      case 'fear':
        return '⚡';
      default:
        return '🎨';
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolvedIconSize = iconSize ?? size * 0.62;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: backgroundColor ?? const Color(0xFFFFF5D8),
        border: Border.all(
          color: borderColor ?? const Color(0xFFE0B465),
          width: size <= 10 ? 0.8 : 1.1,
        ),
        boxShadow: elevation
            ? const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 2.5,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        emojiFor(emotionKey),
        textAlign: TextAlign.center,
        strutStyle: StrutStyle(
          fontSize: resolvedIconSize,
          height: 1,
          forceStrutHeight: true,
        ),
        style: TextStyle(
          fontSize: resolvedIconSize,
          height: 1,
          fontFamilyFallback: const [
            'Apple Color Emoji',
            'Noto Color Emoji',
            'Segoe UI Emoji',
          ],
        ),
      ),
    );
  }
}
