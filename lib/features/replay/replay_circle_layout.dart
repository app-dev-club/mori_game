import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/game_board_view.dart';

/// リプレイ盤面: 場を中心に playerIds 順で時計回りに全員を配置
class ReplayCircleLayout {
  static const double fieldCardWidth = 72;
  static const double fieldCardHeight = 108;

  final List<Offset> playerCenters;
  final Offset fieldCenter;
  final double handMaxWidth;

  const ReplayCircleLayout({
    required this.playerCenters,
    required this.fieldCenter,
    required this.handMaxWidth,
  });

  factory ReplayCircleLayout.compute(Size area, int playerCount) {
    final fieldCenter = Offset(area.width / 2, area.height / 2);
    if (playerCount <= 0) {
      return ReplayCircleLayout(
        playerCenters: const [],
        fieldCenter: fieldCenter,
        handMaxWidth: area.width * 0.4,
      );
    }

    final radius = math.min(area.width, area.height) * 0.38;
    const startAngle = math.pi / 2;

    final centers = List.generate(playerCount, (i) {
      final theta = startAngle - i * (2 * math.pi / playerCount);
      return Offset(
        fieldCenter.dx + radius * math.cos(theta),
        fieldCenter.dy - radius * math.sin(theta),
      );
    });

    final handMaxWidth = playerCount <= 1
        ? area.width * 0.55
        : (2 * radius * math.sin(math.pi / playerCount) * 0.88)
            .clamp(96.0, 220.0);

    return ReplayCircleLayout(
      playerCenters: centers,
      fieldCenter: fieldCenter,
      handMaxWidth: handMaxWidth,
    );
  }

  static Size panelSize(List<CardWidget> hand, double handMaxWidth) {
    const headerHeight = 34.0;
    const footerHeight = 16.0;
    const horizontalPadding = 16.0;
    if (hand.isEmpty) {
      return const Size(120, headerHeight + 24 + footerHeight);
    }
    final layout = HandCardLayout.compute(
      handMaxWidth,
      hand.length.clamp(1, 7),
    );
    return Size(
      layout.totalWidth(hand.length) + horizontalPadding,
      layout.height + headerHeight + footerHeight,
    );
  }
}
