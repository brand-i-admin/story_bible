import 'package:flutter/material.dart';

/// 시대(eras.code) 별 고유 색상 팔레트.
///
/// 동일 시대는 시대 칩(HomeIntroPanel) 과 지도 폴리곤(StoryMapPanel) 에서
/// 같은 색으로 표현되어 사용자가 "어떤 색이 어디 위치인지" 즉시 매칭 가능.
class EraColors {
  EraColors._();

  /// era_code → 대표 색.
  static const Map<String, Color> byCode = {
    'era_primeval': Color(0xFF5C8D8B), // 청록 (원역사)
    'era_patriarch': Color(0xFFB89A66), // 황토 (족장)
    'era_exodus': Color(0xFFC8723E), // 적갈 (출애굽)
    'era_judges': Color(0xFF6F8F58), // 올리브 (사사)
    'era_monarchy': Color(0xFFD0A23B), // 황금 (왕정)
    'era_exile_return': Color(0xFF7A6BB1), // 자주 (포로/포로후기)
    'era_nt_public_ministry': Color(0xFFC85B5B), // 코랄 (예수 공생애)
    'era_nt_apostolic': Color(0xFF3F8FB6), // 청색 (사도)
    'era_nt_post_apostolic': Color(0xFF8C7B57), // 카키 (후기 사도)
    'era_nt_consummation': Color(0xFFA13F5F), // 와인 (역사의 종결)
  };

  /// 알려지지 않은 era code 의 fallback (같은 코드에는 같은 색이 안정적으로
  /// 부여되도록 hashCode 기반 팔레트 인덱싱).
  static const List<Color> _fallback = [
    Color(0xFFB89A66),
    Color(0xFFC8723E),
    Color(0xFF6F8F58),
    Color(0xFF7A6BB1),
    Color(0xFF3F8FB6),
    Color(0xFFD0A23B),
    Color(0xFFA13F5F),
    Color(0xFF5C8D8B),
    Color(0xFF8C7B57),
    Color(0xFFC85B5B),
  ];

  static Color forCode(String? code) {
    if (code == null) return _fallback[0];
    final hit = byCode[code];
    if (hit != null) return hit;
    return _fallback[code.hashCode.abs() % _fallback.length];
  }
}
