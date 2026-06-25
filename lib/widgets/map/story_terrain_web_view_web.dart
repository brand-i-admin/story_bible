// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

class StoryTerrainWebViewController {
  _StoryTerrainWebViewState? _state;

  Future<void> runJavaScript(String script) {
    return _state?._runJavaScript(script) ?? Future<void>.value();
  }
}

class StoryTerrainWebView extends StatefulWidget {
  const StoryTerrainWebView({
    super.key,
    required this.controller,
    required this.html,
    required this.bridgeId,
    required this.onMessage,
  });

  final StoryTerrainWebViewController controller;
  final String html;
  final String bridgeId;
  final ValueChanged<String> onMessage;

  @override
  State<StoryTerrainWebView> createState() => _StoryTerrainWebViewState();
}

class _StoryTerrainWebViewState extends State<StoryTerrainWebView> {
  late final String _viewType =
      'story-terrain-map-${DateTime.now().microsecondsSinceEpoch}';
  late final html.IFrameElement _iframe;
  StreamSubscription<html.MessageEvent>? _messageSub;
  String? _objectUrl;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _iframe = html.IFrameElement()
      ..style.border = '0'
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.display = 'block'
      ..style.backgroundColor = '#e5d2b5'
      ..allow = 'fullscreen'
      ..setAttribute('aria-label', '성경 이야기 3D 지도');
    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int viewId) => _iframe,
    );
    _messageSub = html.window.onMessage.listen(_handleMessage);
    _loadHtml(widget.html);
  }

  @override
  void didUpdateWidget(covariant StoryTerrainWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller._state == this) {
        oldWidget.controller._state = null;
      }
      widget.controller._state = this;
    }
    if (oldWidget.html != widget.html) {
      _loadHtml(widget.html);
    }
  }

  @override
  void dispose() {
    if (widget.controller._state == this) {
      widget.controller._state = null;
    }
    _messageSub?.cancel();
    _iframe.remove();
    _revokeObjectUrl();
    super.dispose();
  }

  void _loadHtml(String htmlText) {
    _revokeObjectUrl();
    final blob = html.Blob([htmlText], 'text/html');
    final nextUrl = html.Url.createObjectUrlFromBlob(blob);
    _objectUrl = nextUrl;
    _iframe.src = nextUrl;
  }

  void _revokeObjectUrl() {
    final objectUrl = _objectUrl;
    if (objectUrl == null) {
      return;
    }
    html.Url.revokeObjectUrl(objectUrl);
    _objectUrl = null;
  }

  Future<void> _runJavaScript(String script) async {
    _iframe.contentWindow?.postMessage({
      'type': 'storyBibleEval',
      'bridgeId': widget.bridgeId,
      'script': script,
    }, '*');
  }

  void _handleMessage(html.MessageEvent event) {
    final raw = event.data;
    final text = raw is String ? raw : jsonEncode(raw);
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map && decoded['bridgeId'] != widget.bridgeId) {
        return;
      }
    } catch (_) {
      return;
    }
    widget.onMessage(text);
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
