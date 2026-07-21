import 'package:flutter/material.dart';

import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';

/// 지도 위에 떠 있는 흐릿한 안내 문구. 사용자가 무엇을 해야 할지 모를 때
/// 화면 가운데에 잠시 보여주고, 사용자가 한 번 행동(폴리곤 탭·줌·인물 선택
/// 후 다음 등)하면 부모가 visible=false 로 dismiss 한다.
///
/// 입력 차단을 안 하므로 hint 가 떠 있어도 그 아래의 폴리곤·핀은 정상 클릭
/// 가능 (부모에서 IgnorePointer 로 감싸 사용).
class MapHintOverlay extends StatelessWidget {
  const MapHintOverlay({
    super.key,
    required this.message,
    this.avatarSize = _guideAvatarSize,
    this.avatarAssetPath = 'assets/avatars_thumbs/guide.png',
    this.showAvatar = true,
    this.checklistStates,
  });

  final String message;
  final double avatarSize;
  final String avatarAssetPath;
  final bool showAvatar;
  final Map<String, bool>? checklistStates;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final outerColor = _guideOuterColor(palette);
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth.isFinite
            ? (constraints.maxWidth - 44).clamp(1.0, 410.0).toDouble()
            : 410.0;
        return Center(
          child: FittedBox(
            key: const ValueKey('map-hint-scale-to-fit'),
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: contentWidth,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    child: Container(
                      key: const ValueKey('map-hint-container'),
                      transform: Matrix4.translationValues(
                        0,
                        _guideOuterTranslationY,
                        0,
                      ),
                      padding: const EdgeInsets.fromLTRB(
                        15,
                        AppSpacing.x5,
                        15,
                        AppSpacing.x3,
                      ),
                      decoration: BoxDecoration(
                        color: outerColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: palette.utilityBorder.withValues(alpha: 0.58),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: palette.primaryDeep.withValues(alpha: 0.16),
                            blurRadius: 18,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        key: const ValueKey('map-hint-message-row'),
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          if (showAvatar) ...[
                            _GuideAvatar(
                              key: const ValueKey('map-hint-avatar'),
                              assetPath: avatarAssetPath,
                              size: avatarSize,
                            ),
                            const SizedBox(width: _guideAvatarGap),
                          ],
                          Expanded(
                            child: _GuideSpeechBubble(
                              message: message,
                              checklistStates: checklistStates,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Positioned(
                    top: MapHintDismissBadge.overlapTop,
                    child: MapHintDismissBadge(),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 지도와 오늘 탭 가이드가 함께 사용하는 닫기 안내 배지다.
class MapHintDismissBadge extends StatelessWidget {
  const MapHintDismissBadge({super.key, this.badgeKey});

  static const double overlapTop = -22;

  final Key? badgeKey;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return Container(
      key: badgeKey ?? const ValueKey('map-hint-dismiss-badge'),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: _guideDismissBadgeColor(palette),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(
          color: palette.currentAccent.withValues(alpha: 0.32),
          width: 1,
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.hourglass_top_rounded, color: Colors.white, size: 13),
          SizedBox(width: 6),
          Text(
            '화면 아무데나 누르면 사라집니다',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

const double _guideAvatarGap = 12;
const double _guideAvatarSize = 48;
const double _guideAvatarImageScale = 1.13;
const double _guideOuterTranslationY = -2;

Color _guideOuterColor(AppColorPalette palette) {
  return palette.utilityBackground.withValues(alpha: 0.64);
}

Color _guideDismissBadgeColor(AppColorPalette palette) {
  return Color.alphaBlend(
    palette.currentAccentDeep.withValues(alpha: 0.82),
    palette.utilityBackground,
  ).withValues(alpha: 0.78);
}

Color _guideSpeechBubbleColor(AppColorPalette palette) {
  return Color.alphaBlend(
    palette.characterAccent.withValues(alpha: 0.68),
    palette.utilityBackground,
  ).withValues(alpha: 0.72);
}

Color _guideStepBadgeColor(AppColorPalette palette) {
  return Color.alphaBlend(
    palette.currentAccentDeep.withValues(alpha: 0.70),
    palette.characterAccent,
  ).withValues(alpha: 0.70);
}

TextStyle _guideSpeechTextStyle() {
  return const TextStyle(
    color: Colors.white,
    fontSize: 12.4,
    fontWeight: FontWeight.w700,
    height: 1.38,
    shadows: [],
  );
}

bool _isGuideStepLine(String line) {
  final trimmed = line.trimLeft();
  return trimmed.isNotEmpty &&
      _GuideSpeechMessage.circledDigits.containsKey(trimmed[0]);
}

bool _isGuideBulletLine(String line) {
  return line.trimLeft().startsWith('•');
}

bool _isGuideAsideLine(String line) {
  final trimmed = line.trim();
  return trimmed.startsWith('(') && trimmed.endsWith(')');
}

bool _isEraNavigationAsideLine(String line) {
  final trimmed = line.trim();
  return _isGuideAsideLine(trimmed) &&
      trimmed.contains('시대 다시 선택') &&
      trimmed.contains('시대/방법');
}

class _GuideSpeechBubble extends StatelessWidget {
  const _GuideSpeechBubble({required this.message, this.checklistStates});

  final String message;
  final Map<String, bool>? checklistStates;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final speechBubbleColor = _guideSpeechBubbleColor(palette);
    return Container(
      key: const ValueKey('map-hint-speech-bubble'),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: speechBubbleColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: palette.characterAccent.withValues(alpha: 0.36),
          width: 1,
        ),
      ),
      child: _GuideSpeechMessage(
        message: message,
        checklistStates: checklistStates,
      ),
    );
  }
}

class _GuideSpeechMessage extends StatelessWidget {
  const _GuideSpeechMessage({required this.message, this.checklistStates});

  final String message;
  final Map<String, bool>? checklistStates;

  static const circledDigits = <String, String>{'①': '1', '②': '2', '③': '3'};

  @override
  Widget build(BuildContext context) {
    final textStyle = _guideSpeechTextStyle();
    final lines = message.split('\n');
    final hasStepLines = lines.any(_isStepLine);
    final hasBulletLines = lines.any(_isBulletLine);
    if (!hasStepLines && !hasBulletLines) {
      return Text(message, textAlign: TextAlign.left, style: textStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (index, line) in lines.indexed)
          _isBulletLine(line)
              ? Padding(
                  padding: EdgeInsets.only(top: index == 0 ? 0 : 7),
                  child: _GuideBulletLine(
                    key: ValueKey('map-hint-bullet-$index'),
                    text: line.trimLeft().substring(1).trimLeft(),
                    textStyle: textStyle,
                  ),
                )
              : _isStepLine(line)
              ? Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: _GuideStepLine(
                    number: circledDigits[line.trimLeft()[0]]!,
                    text: line.trimLeft().substring(1).trimLeft(),
                    textStyle: textStyle,
                    completed:
                        checklistStates?[circledDigits[line.trimLeft()[0]]!],
                  ),
                )
              : _isEraNavigationAsideLine(line) && hasBulletLines
              ? Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: _GuideEraNavigationAside(
                    textStyle: textStyle.copyWith(
                      color: Colors.white,
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : _isAsideLine(line) && hasBulletLines
              ? Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: Text(
                    line.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.visible,
                    textAlign: TextAlign.left,
                    style: textStyle.copyWith(
                      color: Colors.white,
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : _isAsideLine(line)
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, left: 25),
                  child: _GuideScaledTextLine(
                    key: ValueKey('map-hint-aside-line-${line.trim()}'),
                    text: line.trim(),
                    style: textStyle.copyWith(
                      color: Colors.white,
                      fontSize: 11.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                )
              : Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _GuideScaledTextLine(
                    key: ValueKey('map-hint-scaled-line-$line'),
                    text: line,
                    style: textStyle,
                  ),
                ),
      ],
    );
  }

  bool _isStepLine(String line) {
    return _isGuideStepLine(line);
  }

  bool _isBulletLine(String line) {
    return _isGuideBulletLine(line);
  }

  bool _isAsideLine(String line) {
    return _isGuideAsideLine(line);
  }
}

class _GuideEraNavigationAside extends StatelessWidget {
  const _GuideEraNavigationAside({required this.textStyle});

  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    final iconColor = textStyle.color ?? Colors.white;
    return RichText(
      key: const ValueKey('map-hint-era-navigation-aside'),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 2,
      overflow: TextOverflow.visible,
      textAlign: TextAlign.left,
      text: TextSpan(
        style: textStyle,
        children: [
          const TextSpan(text: "(다른 시대 선택은 '"),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _GuideEraNavigationIcon(
              ringKey: const ValueKey('map-hint-era-back-icon-ring'),
              iconKey: const ValueKey('map-hint-era-back-icon'),
              icon: Icons.arrow_back_rounded,
              color: iconColor,
              semanticLabel: '시대 다시 선택',
            ),
          ),
          const TextSpan(text: " 시대 다시 선택' 버튼\n혹은 '"),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: _GuideEraNavigationIcon(
              ringKey: const ValueKey('map-hint-era-home-icon-ring'),
              iconKey: const ValueKey('map-hint-era-home-icon'),
              icon: Icons.home_rounded,
              color: iconColor,
              semanticLabel: '시대/방법',
            ),
          ),
          const TextSpan(text: " 시대/방법' 버튼 클릭)"),
        ],
      ),
    );
  }
}

class _GuideEraNavigationIcon extends StatelessWidget {
  const _GuideEraNavigationIcon({
    required this.ringKey,
    required this.iconKey,
    required this.icon,
    required this.color,
    required this.semanticLabel,
  });

  final Key ringKey;
  final Key iconKey;
  final IconData icon;
  final Color color;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ringKey,
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.58)),
      ),
      child: Icon(
        icon,
        key: iconKey,
        color: color,
        size: 10,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

class _GuideBulletLine extends StatelessWidget {
  const _GuideBulletLine({
    super.key,
    required this.text,
    required this.textStyle,
  });

  final String text;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('•', style: textStyle.copyWith(fontWeight: FontWeight.w900)),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.left,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _GuideStepLine extends StatelessWidget {
  const _GuideStepLine({
    required this.number,
    required this.text,
    required this.textStyle,
    this.completed,
  });

  final String number;
  final String text;
  final TextStyle textStyle;
  final bool? completed;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final stepBadgeColor = _guideStepBadgeColor(palette);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (completed != null)
          Padding(
            padding: const EdgeInsets.only(top: 1.5, right: 7),
            child: Icon(
              completed!
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              key: ValueKey(
                'map-hint-check-$number-${completed! ? 'completed' : 'pending'}',
              ),
              color: textStyle.color,
              size: 18,
            ),
          )
        else
          Container(
            key: ValueKey('map-hint-step-badge-$number'),
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1.5, right: 7),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stepBadgeColor,
              border: Border.all(
                color: palette.currentAccent.withValues(alpha: 0.38),
                width: 1,
              ),
            ),
            child: Text(
              number,
              style: textStyle.copyWith(
                fontSize: 10.5,
                height: 1,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        Expanded(
          child: Text(
            text,
            key: ValueKey('map-hint-step-line-$text'),
            maxLines: 2,
            overflow: TextOverflow.visible,
            textAlign: TextAlign.left,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}

class _GuideScaledTextLine extends StatelessWidget {
  const _GuideScaledTextLine({
    super.key,
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final child = Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.visible,
          textAlign: TextAlign.left,
          style: style,
        );
        if (!constraints.maxWidth.isFinite) {
          return child;
        }
        return SizedBox(
          width: constraints.maxWidth,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: child,
          ),
        );
      },
    );
  }
}

class _GuideAvatar extends StatelessWidget {
  const _GuideAvatar({super.key, required this.assetPath, required this.size});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      padding: EdgeInsets.all(size >= 50 ? 3 : 2.4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: palette.softSurface.withValues(alpha: 0.94),
        border: Border.all(
          color: palette.currentAccentDeep.withValues(alpha: 0.74),
          width: size >= 50 ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.primaryDeep.withValues(alpha: 0.24),
            blurRadius: size >= 50 ? 12 : 8,
            offset: Offset(0, size >= 50 ? 4 : 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Transform.scale(
          key: const ValueKey('map-hint-avatar-image-scale'),
          scale: _guideAvatarImageScale,
          alignment: Alignment.center,
          child: Image.asset(
            assetPath,
            key: const ValueKey('map-hint-avatar-image'),
            semanticLabel: '가이드',
            fit: BoxFit.cover,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                color: AppColors.parchmentCard,
                alignment: Alignment.center,
                child: Text(
                  '가이드',
                  style: TextStyle(
                    color: AppColors.ink700,
                    fontSize: size >= 50 ? 11 : 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
