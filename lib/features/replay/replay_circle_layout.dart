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
    return _computeCircleFitted(
      area: area,
      playerIds: playerIds,
      hands: hands,
      panelSizeFor: (id, hand, handMaxWidth) => spectatorPanelSize(
        hand: hand,
        handMaxWidth: handMaxWidth,
        gameStarted: gameStarted,
        hasOpenJoker: openJokerPlayerIds.contains(id),
        compact: _isCompactHandMax(handMaxWidth),
      ),
    );
  }

  /// リプレイ用: 円形配置で手札・パネルが画面内に収まるようスケールを調整
  factory ReplayCircleLayout.computeForReplay({
    required Size area,
    required List<String> playerIds,
    required Map<String, List<CardWidget>> hands,
  }) {
    return _computeCircleFitted(
      area: area,
      playerIds: playerIds,
      hands: hands,
      panelSizeFor: (id, hand, handMaxWidth) => replayPanelSize(
        hand,
        handMaxWidth,
        compact: _isCompactHandMax(handMaxWidth),
      ),
    );
  }

  static Size spectatorPanelSize({
    required List<CardWidget> hand,
    required double handMaxWidth,
    required bool gameStarted,
    required bool hasOpenJoker,
    bool compact = false,
  }) {
    final horizontalPadding = compact ? 8.0 : 12.0;
    final verticalPadding = compact ? 8.0 : 12.0;
    const handTopGap = 6.0;
    final footerHeight = compact ? 12.0 : 14.0;
    var headerHeight = compact ? 26.0 : 30.0;
    if (gameStarted) headerHeight += compact ? 14.0 : 16.0;
    if (hasOpenJoker) headerHeight += compact ? 16.0 : 18.0;

    if (hand.isEmpty) {
      return Size(
        compact ? 84 : 96,
        headerHeight + 20 + footerHeight + verticalPadding,
      );
    }

    final layout = HandCardLayout.computeSpectator(
      handMaxWidth,
      hand.length.clamp(1, 7),
      gap: 4,
    );
    return Size(
      math.max(layout.totalWidth(hand.length) + horizontalPadding, compact ? 64 : 72),
      headerHeight + handTopGap + layout.height + footerHeight + verticalPadding,
    );
  }

  static Size replayPanelSize(
    List<CardWidget> hand,
    double handMaxWidth, {
    bool compact = false,
  }) {
    final horizontalPadding = compact ? 12.0 : 16.0;
    final verticalPadding = compact ? 12.0 : 16.0;
    const handTopGap = 6.0;
    final headerHeight = compact ? 28.0 : 34.0;
    final footerHeight = compact ? 14.0 : 16.0;

    if (hand.isEmpty) {
      return Size(
        compact ? 100 : 120,
        headerHeight + 24 + footerHeight + verticalPadding,
      );
    }

    final layout = HandCardLayout.computeSpectator(
      handMaxWidth,
      hand.length.clamp(1, 7),
      gap: 4,
    );
    return Size(
      math.max(layout.totalWidth(hand.length) + horizontalPadding, compact ? 64 : 72),
      headerHeight + handTopGap + layout.height + footerHeight + verticalPadding,
    );
  }

  static bool _isCompactHandMax(double handMaxWidth) => handMaxWidth < 108;

  static ReplayCircleLayout _computeCircleFitted({
    required Size area,
    required List<String> playerIds,
    required Map<String, List<CardWidget>> hands,
    required Size Function(String playerId, List<CardWidget> hand, double handMaxWidth)
        panelSizeFor,
  }) {
    final margin = area.width < 400 ? 6.0 : 4.0;
    final minPanelGap = area.width < 400 ? 8.0 : 6.0;
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

    const startAngle = math.pi / 2;
    final shortSide = math.min(area.width, area.height);
    final maxRadius = shortSide * 0.48;
    final minRadius = shortSide * 0.11;

    List<Offset> centersFor(double radius) {
      return List.generate(n, (i) {
        final theta = startAngle - i * (2 * math.pi / n);
        return Offset(
          fieldCenter.dx + radius * math.cos(theta),
          fieldCenter.dy - radius * math.sin(theta),
        );
      });
    }

    double chordAt(double radius) {
      return n <= 1 ? area.width * 0.62 : 2 * radius * math.sin(math.pi / n);
    }

    for (var radiusStep = 0; radiusStep < 34; radiusStep++) {
      final radius = maxRadius - (maxRadius - minRadius) * (radiusStep / 33);
      final centers = centersFor(radius);
      final chord = chordAt(radius);

      for (var fieldStep = 0; fieldStep < 14; fieldStep++) {
        final fieldScale = 1.0 - fieldStep * 0.055;
        final fieldW = (_responsiveFieldCardWidth(area) * fieldScale).clamp(22.0, 96.0);
        final fieldH = fieldW * 1.5;

        var tryHandMax = (chord - minPanelGap - 16).clamp(16.0, area.width * 0.44);

        for (var shrink = 0; shrink < 24; shrink++) {
          final panelSizes = <Size>[];
          for (final id in playerIds) {
            final hand = hands[id] ?? const <CardWidget>[];
            panelSizes.add(panelSizeFor(id, hand, tryHandMax));
          }

          final candidate = ReplayCircleLayout(
            playerCenters: centers,
            fieldCenter: fieldCenter,
            handMaxWidth: tryHandMax,
            layoutFieldCardWidth: fieldW,
            layoutFieldCardHeight: fieldH,
          );

          if (_circlePanelsFit(
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

          tryHandMax *= 0.87;
          if (tryHandMax < 14) break;
        }
      }
    }

    return _minimalFittedLayout(
      area: area,
      playerIds: playerIds,
      hands: hands,
      panelSizeFor: panelSizeFor,
      fieldCenter: fieldCenter,
      margin: margin,
      minPanelGap: minPanelGap,
    );
  }

  static ReplayCircleLayout _minimalFittedLayout({
    required Size area,
    required List<String> playerIds,
    required Map<String, List<CardWidget>> hands,
    required Size Function(String playerId, List<CardWidget> hand, double handMaxWidth)
        panelSizeFor,
    required Offset fieldCenter,
    required double margin,
    required double minPanelGap,
  }) {
    const startAngle = math.pi / 2;
    final n = playerIds.length;
    final shortSide = math.min(area.width, area.height);
    final fieldW = 22.0;
    final fieldH = fieldW * 1.5;
    var tryHandMax = 14.0;

    for (var radiusStep = 0; radiusStep < 40; radiusStep++) {
      final radius = shortSide * 0.48 - (shortSide * 0.37) * (radiusStep / 39);
      final centers = List.generate(n, (i) {
        final theta = startAngle - i * (2 * math.pi / n);
        return Offset(
          fieldCenter.dx + radius * math.cos(theta),
          fieldCenter.dy - radius * math.sin(theta),
        );
      });

      for (var shrink = 0; shrink < 8; shrink++) {
        final panelSizes = <Size>[];
        for (final id in playerIds) {
          final hand = hands[id] ?? const <CardWidget>[];
          panelSizes.add(panelSizeFor(id, hand, tryHandMax));
        }

        final candidate = ReplayCircleLayout(
          playerCenters: centers,
          fieldCenter: fieldCenter,
          handMaxWidth: tryHandMax,
          layoutFieldCardWidth: fieldW,
          layoutFieldCardHeight: fieldH,
        );

        if (_circlePanelsFit(
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

        tryHandMax = math.max(12.0, tryHandMax - 0.5);
      }
    }

    final fallbackRadius = shortSide * 0.2;
    return ReplayCircleLayout(
      playerCenters: List.generate(n, (i) {
        final theta = startAngle - i * (2 * math.pi / n);
        return Offset(
          fieldCenter.dx + fallbackRadius * math.cos(theta),
          fieldCenter.dy - fallbackRadius * math.sin(theta),
        );
      }),
      fieldCenter: fieldCenter,
      handMaxWidth: 12,
      layoutFieldCardWidth: fieldW,
      layoutFieldCardHeight: fieldH,
    );
  }

  static bool _circlePanelsFit({
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
        if (panelRects[i].inflate(minPanelGap).overlaps(panelRects[j])) {
          return false;
        }
      }
    }

    return true;
  }

  static Size panelSize(List<CardWidget> hand, double handMaxWidth) {
    return replayPanelSize(hand, handMaxWidth, compact: _isCompactHandMax(handMaxWidth));
  }

  static Size panelSizeForSpectator(
    List<CardWidget> hand,
    double handMaxWidth, {
    bool gameStarted = true,
    bool hasOpenJoker = false,
    bool compact = false,
  }) {
    return spectatorPanelSize(
      hand: hand,
      handMaxWidth: handMaxWidth,
      gameStarted: gameStarted,
      hasOpenJoker: hasOpenJoker,
      compact: compact,
    );
  }
}
