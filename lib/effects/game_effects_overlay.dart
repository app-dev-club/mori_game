import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'game_effects.dart';

class GameEffectsOverlay extends StatelessWidget {
  final GameEffects effects;

  const GameEffectsOverlay({
    super.key,
    required this.effects,
  });

  /// もり返しボタン・手札エリアと重ならないよう下側を空ける
  static const double _bottomReservedFraction = 0.40;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: effects,
      builder: (context, _) {
        final visual = effects.activeVisual;
        if (visual == null) return const SizedBox.shrink();

        final media = MediaQuery.of(context);
        final screenSize = media.size;
        final topPadding = media.padding.top;
        final bottomReserved = screenSize.height * _bottomReservedFraction;
        final effectAreaHeight =
            screenSize.height - bottomReserved - topPadding - 24;
        final imageWidth = math.min(
          screenSize.width * 0.88,
          effectAreaHeight * 1.15,
        ).clamp(360.0, 640.0);

        return Positioned.fill(
          child: IgnorePointer(
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  bottom: bottomReserved,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.35),
                  ),
                ),
                Positioned(
                  top: topPadding + 16,
                  left: 16,
                  right: 16,
                  bottom: bottomReserved + 8,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey('${visual.name}-${effects.visualToken}'),
                      tween: Tween(begin: 0.82, end: 1.0),
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      builder: (context, scale, child) => Transform.scale(
                        scale: scale,
                        child: child,
                      ),
                      child: Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.asset(
                            GameEffects.imageAssetFor(visual),
                            width: imageWidth,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
