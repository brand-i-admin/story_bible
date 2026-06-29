import 'package:flutter/material.dart';

import '../theme/tokens.dart';

class ParchmentPageScaffold extends StatelessWidget {
  const ParchmentPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.showBackButton = true,
    this.actions,
    this.compactBackOnly = false,
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final bool showBackButton;
  final List<Widget>? actions;
  final bool compactBackOnly;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Scaffold(
      floatingActionButton: floatingActionButton,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.parchmentLight,
                    AppColors.parchmentMid,
                    AppColors.parchmentWarm,
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.08,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Color(0x00FFFFFF),
                        Color(0x337B9155),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: compactBackOnly
                ? Stack(
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: showBackButton ? 40 : 0,
                            top: 10,
                          ),
                          child: child,
                        ),
                      ),
                      if (showBackButton)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: _CompactBackButton(
                            onTap: () => Navigator.of(context).pop(),
                          ),
                        ),
                    ],
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                        child: Row(
                          children: [
                            if (showBackButton)
                              _HeaderButton(
                                label: '이전',
                                selected: true,
                                onTap: () => Navigator.of(context).pop(),
                              ),
                            if (showBackButton) const SizedBox(width: 12),
                            Expanded(
                              child: Container(
                                constraints: BoxConstraints(
                                  minHeight: largeText ? 52 : 40,
                                ),
                                alignment: Alignment.centerLeft,
                                padding: EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: largeText ? 8 : 0,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.floatingSurfaceDefault,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: AppColors.borderFloating,
                                    width: 1.15,
                                  ),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color(0x16000000),
                                      blurRadius: 8,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  title,
                                  maxLines: largeText ? 2 : 1,
                                  overflow: largeText
                                      ? TextOverflow.visible
                                      : TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: const TextStyle(
                                    color: AppColors.ink500,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                            if (actions != null && actions!.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              ...actions!,
                            ],
                          ],
                        ),
                      ),
                      Expanded(child: child),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class ParchmentCard extends StatelessWidget {
  const ParchmentCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color = AppColors.floatingSurfaceDefault,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.borderFloating, width: 1.15),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class ParchmentListPageScaffold extends StatelessWidget {
  const ParchmentListPageScaffold({
    super.key,
    required this.title,
    required this.child,
    this.onBack,
    this.bodyPadding = const EdgeInsets.fromLTRB(14, 58, 14, 14),
    this.headerPadding = const EdgeInsets.fromLTRB(14, 8, 14, 0),
  });

  final String title;
  final Widget child;
  final VoidCallback? onBack;
  final EdgeInsetsGeometry bodyPadding;
  final EdgeInsetsGeometry headerPadding;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.parchmentLight,
                    AppColors.parchmentMid,
                    AppColors.parchmentWarm,
                  ],
                ),
              ),
            ),
          ),
          const Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.08,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        Color(0x00FFFFFF),
                        Color(0x337B9155),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Padding(padding: bodyPadding, child: child),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: headerPadding,
                child: ParchmentListPageHeader(title: title, onBack: onBack),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ParchmentListPageHeader extends StatelessWidget {
  const ParchmentListPageHeader({super.key, required this.title, this.onBack});

  final String title;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Row(
      children: [
        ParchmentIconBackButton(
          onTap: onBack ?? () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            maxLines: largeText ? 2 : 1,
            overflow: largeText ? TextOverflow.visible : TextOverflow.ellipsis,
            softWrap: true,
            style: const TextStyle(
              color: AppColors.ink800,
              fontSize: 18,
              fontWeight: FontWeight.w900,
              height: 1.15,
            ),
          ),
        ),
      ],
    );
  }
}

class ParchmentIconBackButton extends StatelessWidget {
  const ParchmentIconBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xD06A401E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.goldRim, width: 1.4),
            boxShadow: const [
              BoxShadow(
                color: Color(0x24000000),
                blurRadius: 10,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 17,
            color: AppColors.fgOnDark,
          ),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppColors.brownWarm2 : AppColors.ink800,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.goldRim : const Color(0xBFD8BF99),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.fgOnDark,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactBackButton extends StatelessWidget {
  const _CompactBackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xD06A401E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.goldRim, width: 1.4),
          ),
          child: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 16,
            color: AppColors.fgOnDark,
          ),
        ),
      ),
    );
  }
}
