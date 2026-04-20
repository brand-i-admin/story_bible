/// 앱 전역 글자 크기 배율.
///
/// `MediaQuery.textScaler`에 주입되어 모든 `Text` 위젯에 자동 적용된다.
/// SharedPreferences에는 [storageKey] 문자열로 저장한다.
enum FontScale {
  small(0.9, '작게'),
  normal(1.0, '보통'),
  large(1.2, '크게');

  const FontScale(this.ratio, this.label);

  final double ratio;
  final String label;

  String get storageKey => name;

  static FontScale fromStorage(String? raw) => switch (raw) {
    'small' => FontScale.small,
    'large' => FontScale.large,
    _ => FontScale.normal,
  };
}
