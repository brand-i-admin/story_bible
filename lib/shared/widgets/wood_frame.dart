import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

class WoodFrame extends StatelessWidget {
  const WoodFrame({
    super.key,
    required this.child,
    this.innerPadding = const EdgeInsets.all(12),
  });

  final Widget child;
  final EdgeInsets innerPadding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.woodLight, AppColors.woodMid],
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(2.5),
      child: Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFF5EDD5), AppColors.parchMid],
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: innerPadding,
        child: child,
      ),
    );
  }
}
