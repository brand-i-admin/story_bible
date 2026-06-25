import 'package:flutter/widgets.dart';

class StoryTerrainWebViewController {
  Future<void> runJavaScript(String script) async {}
}

class StoryTerrainWebView extends StatelessWidget {
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
