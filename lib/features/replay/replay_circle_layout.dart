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

  /// 観戦用: 円形配置で手札・パネルが画面内に収まるようスケールを調整
  factory ReplayCircleLayout.computeForSpectator({
    required Size area,
    required List<String> playerIds,
    required Map<String, List<CardWidget>> hands,
    Set<String> openJokerPlayerIds = const {},
    bool gameStarted = true,
  }) {
    return _computeSpectatorFitted(
      area: area,
      playerIds: playerIds,
      hands: hands,
      openJokerPlayerIds: openJokerPlayerIds,
      gameStarted: gameStarted,
    );
  }

  static Size spectatorPanelSize({
    required List<CardWidget> hand,
    required double handMaxWidth,
    required bool gameStarted,
    required bool hasOpenJoker,
  }) {
    const horizontalPadding = 12.0;
    const verticalPadding = 12.0;
    const handTopGap = 6.0;
    const footerHeight = 14.0;
    var headerHeight = 30.0;
    if (gameStarted) headerHeight += 16;
    if (hasOpenJoker) headerHeight += 18;

    if (hand.isEmpty) {
      return Size(
        96,
        headerHeight + 20 + footerHeight + verticalPadding,
      );
    }

    final layout = HandCardLayout.computeSpectator(
      handMaxWidth,
      hand.length.clamp(1, 7),
      gap: 4,
    );
    return Size(
      math.max(layout.totalWidth(hand.length) + horizontalPadding, 72),
      headerHeight + handTopGap + layout.height + footerHeight + verticalPadding,
    );
  }

  static ReplayCircleLayout _computeSpectatorFitted({
    required Size area,
    required List<String> playerIds,
    required Map<String, List<CardWidget>> hands,
    required Set<String> openJokerPlayerIds,
    required bool gameStarted,
  }) {
    const margin = 4.0;
    const minPanelGap = 6.0;
    final fieldCenter = Offset(area.width / 2, area.height / 2);
    final n = playerIds.length;

    if (n == 0) {
      final fieldW = _responsiveFieldCardWidth(area);
      return ReplayCircleLayout(
        playerCenters: const [],
        fieldCenter: fieldCenter,
        handMaxWidth: area.width * 0.5,
        layoutFieldCardWidth: fieldW,
        layoutFieldCardHeight: fieldW * 1.5,
      );
    }

    ReplayCircleLayout? best;
    var scale = 1.0;

    for (var attempt = 0; attempt < 40; attempt++) {
      final fieldW = (_responsiveFieldCardWidth(area) * scale).clamp(28.0, 96.0);
      final fieldH = fieldW * 1.5;
      final shortSide = math.min(area.width, area.height);
      final radius = (shortSide * 0.40 * scale).clamp(shortSide * 0.14, shortSide * 0.44);

      final chord = n <= 1
          ? area.width * 0.68
          : 2 * radius * math.sin(math.pi / n);

      var tryHandMax = (chord * 0.92).clamp(24.0, area.width * 0.48);

      const startAngle = math.pi / 2;
      ReplayCircleLayout? attemptBest;

      for (var shrink = 0; shrink < 18; shrink++) {
        final centers = List.generate(n, (i) {
          final theta = startAngle - i * (2 * math.pi / n);
          return Offset(
            fieldCenter.dx + radius * math.cos(theta),
            fieldCenter.dy - radius * math.sin(theta),
          );
        });

        final panelSizes = <Size>[];
        for (final id in playerIds) {
          final hand = hands[id] ?? const <CardWidget>[];
          panelSizes.add(
            spectatorPanelSize(
              hand: hand,
              handMaxWidth: tryHandMax,
              gameStarted: gameStarted,
              hasOpenJoker: openJokerPlayerIds.contains(id),
            ),
          );
        }

        final candidate = ReplayCircleLayout(
          playerCenters: centers,
          fieldCenter: fieldCenter,
          handMaxWidth: tryHandMax,
          layoutFieldCardWidth: fieldW,
          layoutFieldCardHeight: fieldH,
        );

        if (_spectatorPanelsFit(
          area: area,
          centers: centers,
          panelSizes: panelSizes,
          fieldCenter: fieldCenter,
          fieldSize: Size(fieldW, fieldH),
          margin: margin,
          minPanelGap: minPanelGap,
        )) {
          return candidate;
        }

        attemptBest = candidate;
        tryHandMax *= 0.9;
      }

      if (attemptBest != null) {
        best = attemptBest;
      }
      scale *= 0.87;
    }

    return best ?? ReplayCircleLayout.compute(area, n);
  }

  static bool _spectatorPanelsFit({
    required Size area,
    required List<Offset> centers,
    required List<Size> panelSizes,
    required Offset fieldCenter,
    required Size fieldSize,
    double margin = 4,
    double minPanelGap = 6,
  }) {
    final fieldRect = Rect.fromCenter(
      center: fieldCenter,
      width: fieldSize.width,
      height: fieldSize.height,
    ).inflate(minPanelGap);

    final panelRects = <Rect>[];
    for (var i = 0; i < centers.length; i++) {
      final rect = Rect.fromCenter(
        center: centers[i],
        width: panelSizes[i].width,
        height: panelSizes[i].height,
      );
      if (rect.left < margin ||
          rect.top < margin ||
          rect.right > area.width - margin ||
          rect.bottom > area.height - margin) {
        return false;
      }
      if (fieldRect.overlaps(rect)) return false;
      panelRects.add(rect);
    }

    for (var i = 0; i < panelRects.length; i++) {
      for (var j = i + 1; j < panelRects.length; j++) {
        if (panelRects[i].inflate(minPanelGap / 2).overlaps(panelRects[j])) {
          return false;
        }
      }
    }

    return true;
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

  static Size panelSizeForSpectator(
    List<CardWidget> hand,
    double handMaxWidth, {
    bool gameStarted = true,
    bool hasOpenJoker = false,
  }) {
    return spectatorPanelSize(
      hand: hand,
      handMaxWidth: handMaxWidth,
      gameStarted: gameStarted,
      hasOpenJoker: hasOpenJoker,
    );
  }
}
