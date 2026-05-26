import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class EmotionBadgeIcon extends StatelessWidget {
  const EmotionBadgeIcon({
    super.key,
    required this.emotionKey,
    this.size = 18,
    this.iconSize,
    this.backgroundColor,
    this.borderColor,
    this.iconColor,
    this.elevation = true,
  });

  final String emotionKey;
  final double size;
  final double? iconSize;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? iconColor;
  final bool elevation;

  static IconData iconFor(String emotionKey) {
    switch (emotionKey) {
      case 'joy':
        return Icons.auto_awesome;
      case 'anticipation':
        return Icons.trending_up;
      case 'gratitude':
        return Icons.favorite;
      case 'wonder':
        return Icons.help_outline;
      case 'sadness':
        return Icons.water_drop_outlined;
      case 'comfort':
        return Icons.eco_outlined;
      case 'fear':
        return Icons.flash_on;
      default:
        return Icons.more_horiz;
    }
  }

  @override
  Widget build(BuildContext context) {
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
      child: Icon(
        iconFor(emotionKey),
        size: iconSize ?? size * 0.62,
        color: iconColor ?? AppColors.ink500,
      ),
    );
  }
}
