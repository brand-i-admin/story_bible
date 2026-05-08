import 'package:latlong2/latlong.dart';

/// 점이 폴리곤 내부에 있는지 ray-casting 알고리즘으로 판정.
///
/// 정점 수가 적은 region(보통 5–30 vertex) 에 대해 충분히 빠르다.
/// 경계선 위 점은 구현상 모호할 수 있으나 region 분류 용도에서는 큰 문제 없음.
bool isPointInPolygon(LatLng point, List<LatLng> polygon) {
  if (polygon.length < 3) return false;
  final x = point.longitude;
  final y = point.latitude;
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].longitude;
    final yi = polygon[i].latitude;
    final xj = polygon[j].longitude;
    final yj = polygon[j].latitude;
    final intersect =
        ((yi > y) != (yj > y)) &&
        (x < (xj - xi) * (y - yi) / (yj - yi + 0.0) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

/// 폴리곤의 산술 평균 중심(centroid 가 아닌 단순 평균). region 라벨/마커 위치
/// 결정 용도. 정밀한 면적 가중 centroid 가 필요 없으므로 비용을 아낀다.
LatLng polygonCenter(List<LatLng> polygon) {
  if (polygon.isEmpty) return const LatLng(0, 0);
  var lat = 0.0;
  var lng = 0.0;
  for (final p in polygon) {
    lat += p.latitude;
    lng += p.longitude;
  }
  return LatLng(lat / polygon.length, lng / polygon.length);
}
