import 'package:flutter/widgets.dart';

class WebPointerInterceptor extends StatelessWidget {
  const WebPointerInterceptor({
    super.key,
    required this.child,
    this.intercepting = true,
  });

  final Widget child;
  final bool intercepting;

  @override
  Widget build(BuildContext context) => child;
}
