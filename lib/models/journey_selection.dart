enum JourneySource { all, segments, book, person }

enum JourneyScope { all, units, targetOnly }

/// 오늘 홈에서 사용할 이야기 여정 필터.
///
/// 이야기 수와 진행 수치는 저장하지 않고 현재 DB 카탈로그에서 다시 계산한다.
/// SharedPreferences에는 사용자가 고른 조건만 남겨 콘텐츠 추가 뒤에도 자동으로
/// 최신 이야기가 포함되게 한다.
class JourneySelection {
  const JourneySelection({
    required this.source,
    required this.scope,
    this.bookName,
    this.personCode,
    this.personName,
    this.unitKeys = const <String>{},
  });

  const JourneySelection.all()
    : source = JourneySource.all,
      scope = JourneyScope.all,
      bookName = null,
      personCode = null,
      personName = null,
      unitKeys = const <String>{};

  factory JourneySelection.fromMap(Map<String, dynamic> map) {
    final source = JourneySource.values
        .where((value) => value.name == map['source'])
        .firstOrNull;
    final scope = JourneyScope.values
        .where((value) => value.name == map['scope'])
        .firstOrNull;
    if (source == null || scope == null) {
      return const JourneySelection.all();
    }
    final rawUnitKeys = map['unit_keys'];
    return JourneySelection(
      source: source,
      scope: scope,
      bookName: _nonEmptyString(map['book_name']),
      personCode: _nonEmptyString(map['person_code']),
      personName: _nonEmptyString(map['person_name']),
      unitKeys: rawUnitKeys is List
          ? rawUnitKeys
                .map((value) => value?.toString().trim() ?? '')
                .where((value) => value.isNotEmpty)
                .toSet()
          : const <String>{},
    );
  }

  final JourneySource source;
  final JourneyScope scope;
  final String? bookName;
  final String? personCode;
  final String? personName;
  final Set<String> unitKeys;

  Map<String, dynamic> toMap() => {
    'source': source.name,
    'scope': scope.name,
    if (bookName != null) 'book_name': bookName,
    if (personCode != null) 'person_code': personCode,
    if (personName != null) 'person_name': personName,
    'unit_keys': unitKeys.toList()..sort(),
  };

  String get boundaryLabel => switch (source) {
    JourneySource.segments => '선택된 시대',
    JourneySource.book when scope == JourneyScope.targetOnly => '선택된 성경책',
    JourneySource.book => '선택된 시대',
    JourneySource.person when scope == JourneyScope.targetOnly => '선택된 인물',
    JourneySource.person => '선택된 시대',
    JourneySource.all => '전체 여정',
  };

  String get displayLabel => switch (source) {
    JourneySource.all => '전체 순서',
    JourneySource.segments => '일부 구간',
    JourneySource.book when scope == JourneyScope.targetOnly =>
      '${bookName ?? '성경책'} 이야기만',
    JourneySource.book => '${bookName ?? '성경책'} · 시대 구간',
    JourneySource.person when scope == JourneyScope.targetOnly =>
      '${personName ?? '인물'} 이야기만',
    JourneySource.person => '${personName ?? '인물'} · 시대 구간',
  };

  static String? _nonEmptyString(dynamic value) {
    final normalized = value?.toString().trim() ?? '';
    return normalized.isEmpty ? null : normalized;
  }
}
