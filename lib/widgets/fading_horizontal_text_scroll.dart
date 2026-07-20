import 'package:flutter/material.dart';

/// 한 줄 제목을 직접 가로로 밀어 확인할 수 있게 우측 끝을 흐리게 표시한다.
class FadingHorizontalTextScroll extends StatefulWidget {
  const FadingHorizontalTextScroll({
    super.key,
    required this.text,
    required this.style,
    this.scrollKey,
    this.textKey,
    this.alignment = Alignment.centerLeft,
    this.textScaler = TextScaler.noScaling,
  });

  final String text;
  final TextStyle? style;
  final Key? scrollKey;
  final Key? textKey;
  final AlignmentGeometry alignment;
  final TextScaler textScaler;

  @override
  State<FadingHorizontalTextScroll> createState() =>
      _FadingHorizontalTextScrollState();
}

class _FadingHorizontalTextScrollState
    extends State<FadingHorizontalTextScroll> {
  final ScrollController _scrollController = ScrollController();
  bool _hasOverflow = false;
  bool _atEnd = true;
  bool _overflowCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_syncScrollState);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_syncScrollState)
      ..dispose();
    super.dispose();
  }

  void _scheduleOverflowCheck() {
    if (_overflowCheckScheduled) return;
    _overflowCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overflowCheckScheduled = false;
      if (!mounted) return;
      _syncScrollState();
    });
  }

  void _syncScrollState() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final hasOverflow = position.maxScrollExtent > 0;
    final atEnd =
        !hasOverflow || position.pixels >= position.maxScrollExtent - 1;
    if (hasOverflow == _hasOverflow && atEnd == _atEnd) return;
    setState(() {
      _hasOverflow = hasOverflow;
      _atEnd = atEnd;
    });
  }

  @override
  Widget build(BuildContext context) {
    _scheduleOverflowCheck();
    final showRightFade = _hasOverflow && !_atEnd;
    return Semantics(
      label: widget.text,
      child: ExcludeSemantics(
        child: ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            stops: const [0.0, 0.68, 0.88, 1.0],
            colors: [
              Colors.white,
              Colors.white,
              showRightFade ? const Color(0x88FFFFFF) : Colors.white,
              showRightFade ? const Color(0x00FFFFFF) : Colors.white,
            ],
          ).createShader(bounds),
          blendMode: BlendMode.dstIn,
          child: SingleChildScrollView(
            key: widget.scrollKey,
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const ClampingScrollPhysics(),
            child: Align(
              alignment: widget.alignment,
              child: Text(
                widget.text,
                key: widget.textKey,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                textScaler: widget.textScaler,
                style: widget.style,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
