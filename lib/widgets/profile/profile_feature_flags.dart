/// 프로필 도메인의 보류 기능 플래그.
///
/// 기도 기능은 DB/모델/repository/위젯 코드를 보존하되, 제품 화면에서는 잠시
/// 숨긴 pending 상태로 둔다. 다시 열 때 이 값만 false로 바꾸면 기존 배관을
/// 재사용할 수 있다.
bool get profilePrayerFeaturePending => true;
