import 'package:flutter/material.dart';

class AppColors {
  static const Color navy = Color(0xFF0A1F44);
  static const Color teal = Color(0xFF0B3D3A);
  static const Color parchment = Color(0xFFF6F1E7);
  static const Color ink = Color(0xFF1B2A32);
  static const Color gold = Color(0xFFC9A227);
  static const Color sage = Color(0xFF7C9885);
}

class AppBackground extends StatelessWidget {
  final Widget child;
  const AppBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    // FIXED: StackFit.expand tells the Stack to force ALL non-positioned
    // children to fill its full size automatically. This replaces the
    // earlier Positioned.fill approach, which kept conflicting with
    // IgnorePointer's ParentData requirements. Now:
    // - The gradient Container (non-positioned) fills automatically
    // - The radial glow stays Positioned (a direct Stack child, valid)
    // - child (the real page content, non-positioned) fills automatically
    // No Positioned wrapping is needed on the Containers or on child,
    // which avoids every ParentDataWidget conflict we hit before.
    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.navy, AppColors.teal],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -150,
          left: 0,
          right: 0,
          height: 500,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [AppColors.gold.withValues(alpha: 0.18), Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}