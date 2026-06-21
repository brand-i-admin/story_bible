import 'package:flutter/material.dart';

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
  });

  final String message;
  final double avatarSize;
  final String avatarAssetPath;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        margin: const EdgeInsets.symmetric(horizontal: 22),
        constraints: const BoxConstraints(maxWidth: 410),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.54),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.24),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.30),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: Container(
                  key: const ValueKey('map-hint-dismiss-badge'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.20),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.hourglass_top_rounded,
                        color: Colors.white.withValues(alpha: 0.86),
                        size: 13,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '화면 아무데나 누르면 사라집니다',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                key: const ValueKey('map-hint-message-row'),
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _GuideAvatar(
                    key: const ValueKey('map-hint-avatar'),
                    assetPath: avatarAssetPath,
                    size: avatarSize,
                  ),
                  const SizedBox(width: _guideAvatarGap),
                  Expanded(child: _GuideSpeechBubble(message: message)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const double _guideAvatarGap = 12;
const double _guideAvatarSize = 48;
const double _guideAvatarImageScale = 1.13;

TextStyle _guideSpeechTextStyle() {
  return TextStyle(
    color: Colors.white.withValues(alpha: 0.96),
    fontSize: 12.4,
    fontWeight: FontWeight.w700,
    height: 1.38,
    shadows: const [],
  );
}

bool _isGuideStepLine(String line) {
  final trimmed = line.trimLeft();
  return trimmed.isNotEmpty &&
      _GuideSpeechMessage.circledDigits.containsKey(trimmed[0]);
}

bool _isGuideAsideLine(String line) {
  final trimmed = line.trim();
  return trimmed.startsWith('(') && trimmed.endsWith(')');
}

class _GuideSpeechBubble extends StatelessWidget {
  const _GuideSpeechBubble({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('map-hint-speech-bubble'),
      padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.27),
          width: 1,
        ),
      ),
      child: _GuideSpeechMessage(message: message),
    );
  }
}

class _GuideSpeechMessage extends StatelessWidget {
  const _GuideSpeechMessage({required this.message});

  final String message;

  static const circledDigits = <String, String>{'①': '1', '②': '2', '③': '3'};

  @override
  Widget build(BuildContext context) {
    final textStyle = _guideSpeechTextStyle();
    final lines = message.split('\n');
    final hasStepLines = lines.any(_isStepLine);
    if (!hasStepLines) {
      return Text(message, textAlign: TextAlign.left, style: textStyle);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in lines)
          _isStepLine(line)
              ? Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: _GuideStepLine(
                    number: circledDigits[line.trimLeft()[0]]!,
                    text: line.trimLeft().substring(1).trimLeft(),
                    textStyle: textStyle,
                  ),
                )
              : _isAsideLine(line)
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, left: 25),
                  child: _GuideScaledTextLine(
                    key: ValueKey('map-hint-aside-line-${line.trim()}'),
                    text: line.trim(),
                    style: textStyle.copyWith(
                      color: Colors.white.withValues(alpha: 0.84),
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

  bool _isAsideLine(String line) {
    return _isGuideAsideLine(line);
  }
}

class _GuideStepLine extends StatelessWidget {
  const _GuideStepLine({
    required this.number,
    required this.text,
    required this.textStyle,
  });

  final String number;
  final String text;
  final TextStyle textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: ValueKey('map-hint-step-badge-$number'),
          width: 18,
          height: 18,
          margin: const EdgeInsets.only(top: 1.5, right: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.18),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.44),
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      padding: EdgeInsets.all(size >= 50 ? 3 : 2.4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.parchmentCream.withValues(alpha: 0.92),
        border: Border.all(
          color: AppColors.goldDeep.withValues(alpha: 0.72),
          width: size >= 50 ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.30),
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
