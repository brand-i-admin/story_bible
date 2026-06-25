// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class WebPointerInterceptor extends StatefulWidget {
  const WebPointerInterceptor({
    super.key,
    required this.child,
    this.intercepting = true,
  });

  final Widget child;
  final bool intercepting;

  @override
  State<WebPointerInterceptor> createState() => _WebPointerInterceptorState();
}

class _WebPointerInterceptorState extends State<WebPointerInterceptor> {
  late final String _viewType =
      'story-bible-pointer-interceptor-${DateTime.now().microsecondsSinceEpoch}';
  late final html.DivElement _element;

  @override
  void initState() {
    super.initState();
    _element = html.DivElement()
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'transparent'
      ..style.pointerEvents = widget.intercepting ? 'auto' : 'none'
      ..setAttribute('aria-hidden', 'true');
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _element,
      isVisible: false,
    );
  }

  @override
  void didUpdateWidget(covariant WebPointerInterceptor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.intercepting != widget.intercepting) {
      _element.style.pointerEvents = widget.intercepting ? 'auto' : 'none';
    }
  }

  @override
  void dispose() {
    _element.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.intercepting) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: HtmlElementView(viewType: _viewType)),
        widget.child,
      ],
    );
  }
}
