import 'package:flutter/material.dart';

import '../../theme/app_color_palette.dart';
import '../../theme/tokens.dart';

class ProfileGlowingAddButton extends StatefulWidget {
  const ProfileGlowingAddButton({
    super.key,
    required this.tooltip,
    required this.onTap,
    this.size = 34,
    this.iconSize = 22,
    this.backgroundColor = AppColors.greenTint2,
    this.foregroundColor = AppColors.greenBot,
    this.disabledBackgroundColor,
    this.disabledForegroundColor,
    this.pulseDuration = const Duration(milliseconds: 760),
    this.pulseCount = 2,
  }) : assert(pulseCount == null || pulseCount > 0);

  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? disabledBackgroundColor;
  final Color? disabledForegroundColor;
  final Duration pulseDuration;
  final int? pulseCount;

  @override
  State<ProfileGlowingAddButton> createState() =>
      _ProfileGlowingAddButtonState();
}

class _ProfileGlowingAddButtonState extends State<ProfileGlowingAddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool get _enabled => widget.onTap != null;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.pulseDuration,
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant ProfileGlowingAddButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pulseDuration != widget.pulseDuration) {
      _controller.duration = widget.pulseDuration;
    }
    if (oldWidget.onTap != widget.onTap ||
        oldWidget.pulseCount != widget.pulseCount) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (_enabled) {
      if (widget.pulseCount == null) {
        _controller.repeat(reverse: true);
      } else {
        _controller.repeat(reverse: true, count: widget.pulseCount);
      }
    } else {
      _controller
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPaletteTheme.of(context);
    final enabled = _enabled;
    final fillColor = enabled
        ? widget.backgroundColor
        : widget.disabledBackgroundColor ?? AppColors.parchmentCream;
    final iconColor = enabled
        ? widget.foregroundColor
        : widget.disabledForegroundColor ?? AppColors.ink200;

    return Tooltip(
      message: widget.tooltip,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final pulse = enabled ? _controller.value : 0.0;
          final ringScale = 1.12 + pulse * 0.34;
          final ringOpacity = 0.70 - pulse * 0.34;
          final buttonScale = enabled ? 1.0 + pulse * 0.018 : 1.0;
          final ringColor = Color.alphaBlend(
            Colors.white.withValues(alpha: 0.88),
            palette.successTop,
          ).withValues(alpha: ringOpacity);
          return Transform.scale(
            scale: buttonScale,
            child: SizedBox.square(
              dimension: widget.size,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (enabled)
                    Positioned.fill(
                      child: Transform.scale(
                        key: const ValueKey('profile-add-button-pulse-ring'),
                        scale: ringScale,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: ringColor, width: 1.6),
                            boxShadow: [
                              BoxShadow(
                                color: widget.foregroundColor.withValues(
                                  alpha: 0.18 + pulse * 0.16,
                                ),
                                blurRadius: 9 + pulse * 9,
                                spreadRadius: 0.4 + pulse * 1.0,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  child!,
                ],
              ),
            ),
          );
        },
        child: Material(
          color: fillColor,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: widget.onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: Icon(
                Icons.add_rounded,
                size: widget.iconSize,
                color: iconColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
