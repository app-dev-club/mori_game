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
  final double layoutFieldCardWidth;
  final double layoutFieldCardHeight;

  const ReplayCircleLayout({
    required this.playerCenters,
    required this.fieldCenter,
    required this.handMaxWidth,
    double? layoutFieldCardWidth,
    double? layoutFieldCardHeight,
  })  : layoutFieldCardWidth = layoutFieldCardWidth ?? fieldCardWidth,
        layoutFieldCardHeight = layoutFieldCardHeight ?? fieldCardHeight;

  static double _responsiveFieldCardWidth(Size area) {
    final isWide = area.width >= 720;
    return isWide
        ? (area.width * 0.075).clamp(68.0, 96.0)
        : (area.width * 0.17).clamp(56.0, 84.0);
  }

  factory ReplayCircleLayout.compute(Size area, int playerCount) {
    final fieldCenter = Offset(area.width / 2, area.height / 2);
    final fieldW = _responsiveFieldCardWidth(area);
    if (playerCount <= 0) {
      return ReplayCircleLayout(
        playerCenters: const [],
        fieldCenter: fieldCenter,
        handMaxWidth: area.width * 0.4,
        layoutFieldCardWidth: fieldW,
        layoutFieldCardHeight: fieldW * 1.5,
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
      layoutFieldCardWidth: fieldW,
      layoutFieldCardHeight: fieldW * 1.5,
    );
  }

  /// 観戦用: プレイヤー間を広げ、手札エリアを少し大きく取る
  factory ReplayCircleLayout.computeForSpectator(Size area, int playerCount) {
    final fieldCenter = Offset(area.width / 2, area.height / 2);
    final fieldW = _responsiveFieldCardWidth(area);
    if (playerCount <= 0) {
      return ReplayCircleLayout(
        playerCenters: const [],
        fieldCenter: fieldCenter,
        handMaxWidth: area.width * 0.5,
        layoutFieldCardWidth: fieldW,
        layoutFieldCardHeight: fieldW * 1.5,
      );
    }

    final radius = math.min(area.width, area.height) * 0.40;

    const startAngle = math.pi / 2;
    final centers = List.generate(playerCount, (i) {
      final theta = startAngle - i * (2 * math.pi / playerCount);
      return Offset(
        fieldCenter.dx + radius * math.cos(theta),
        fieldCenter.dy - radius * math.sin(theta),
      );
    });

    final handMaxWidth = playerCount <= 1
        ? area.width * 0.62
        : (2 * radius * math.sin(math.pi / playerCount) * 0.94)
            .clamp(112.0, 300.0);

    return ReplayCircleLayout(
      playerCenters: centers,
      fieldCenter: fieldCenter,
      handMaxWidth: handMaxWidth,
      layoutFieldCardWidth: fieldW,
      layoutFieldCardHeight: fieldW * 1.5,
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

  static Size panelSizeForSpectator(List<CardWidget> hand, double handMaxWidth) {
    const headerHeight = 32.0;
    const footerHeight = 14.0;
    const horizontalPadding = 12.0;
    if (hand.isEmpty) {
      return const Size(110, headerHeight + 20 + footerHeight);
    }
    final layout = HandCardLayout.computeSpectator(
      handMaxWidth,
      hand.length.clamp(1, 7),
    );
    return Size(
      layout.totalWidth(hand.length) + horizontalPadding,
      layout.height + headerHeight + footerHeight,
    );
  }
}
