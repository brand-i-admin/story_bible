const _expectedErrorFragments = <String>{
  'failed host lookup',
  'network is unreachable',
  'connection timed out',
  'connection reset by peer',
  'socketexception',
  'clientexception',
  'operation was canceled',
  'operation was cancelled',
  'sign in canceled',
  'sign in cancelled',
};

/// 인터넷 단절이나 사용자의 취소처럼 정상적으로 예상되는 실패를 제외한다.
bool shouldReportNonFatalError(Object error) {
  final normalized = error.toString().toLowerCase();
  return !_expectedErrorFragments.any(normalized.contains);
}

/// Supabase 사용자의 생성 시각과 최초 로그인 시각을 비교한다.
///
/// `AuthChangeEvent.signedIn`과 함께 사용하므로 앱 재시작의 initial session에서는
/// 호출하지 않는다. OAuth 공급자별 시각 기록 오차를 고려해 60초까지 허용한다.
bool isLikelyNewAccountSignIn({
  required String createdAt,
  required String? lastSignInAt,
}) {
  final created = DateTime.tryParse(createdAt)?.toUtc();
  final lastSignIn = DateTime.tryParse(lastSignInAt ?? '')?.toUtc();
  if (created == null || lastSignIn == null) {
    return false;
  }
  return lastSignIn.difference(created).abs() <= const Duration(seconds: 60);
}
