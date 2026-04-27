import 'package:flutter/material.dart';

/// 제안 작성 화면에서 캐릭터 아바타 / 장면 이미지를 클릭했을 때 띄우는
/// 풀스크린 확대 다이얼로그. InteractiveViewer 로 핀치 줌·드래그 가능.
///
/// - 빈 공간 탭 또는 우상단 X 버튼으로 닫힘
/// - 로드 중에는 흰 스피너, 실패 시 broken_image 아이콘
/// - 모달 background 는 거의 검정(92% opacity) 으로 원본 이미지 가시성 우선
Future<void> showImageZoomDialog(BuildContext context, {required String url}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.85),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // 빈 공간 탭으로 닫기.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
            ),
          ),
          // 이미지 — 화면 안에서 가능한 최대 크기, 원본 비율 유지.
          Center(
            child: InteractiveViewer(
              maxScale: 5,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white70,
                  size: 80,
                ),
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
              ),
            ),
          ),
          // 닫기 버튼.
          Positioned(
            top: 16,
            right: 16,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(ctx).pop(),
                icon: const Icon(Icons.close, color: Colors.white, size: 26),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
