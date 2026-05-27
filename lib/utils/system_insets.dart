import 'package:flutter/widgets.dart';

/// 하단 시스템 영역이 실제 내비게이션/홈 인디케이터인지 판단하는 기준값.
///
/// 일부 모바일 WebView/브라우저 조합은 내비게이션 바가 없어도 몇 px 정도의
/// bottom padding 을 보고한다. 그 값을 그대로 SafeArea/하단 시트에 반영하면
/// 화면 맨 아래에 의미 없는 빈 틈이 생기므로 작은 값은 0 으로 취급한다.
const double meaningfulBottomSystemInsetThreshold = 16;

double effectiveBottomSystemInset(double rawBottomInset) {
  return rawBottomInset >= meaningfulBottomSystemInsetThreshold
      ? rawBottomInset
      : 0;
}

MediaQueryData normalizeTinyBottomSystemInset(MediaQueryData media) {
  final effectivePaddingBottom = effectiveBottomSystemInset(
    media.padding.bottom,
  );
  final effectiveViewPaddingBottom = effectiveBottomSystemInset(
    media.viewPadding.bottom,
  );

  if (effectivePaddingBottom == media.padding.bottom &&
      effectiveViewPaddingBottom == media.viewPadding.bottom) {
    return media;
  }

  return media.copyWith(
    padding: media.padding.copyWith(bottom: effectivePaddingBottom),
    viewPadding: media.viewPadding.copyWith(bottom: effectiveViewPaddingBottom),
  );
}
