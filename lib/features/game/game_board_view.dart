import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../logic/game_rules.dart';
import '../../logic/morrie_rules.dart';
import '../../logic/player_display_name.dart';
import '../../logic/room_config.dart';
import '../../models/post_game_summary.dart';
import '../common/app_side_bar.dart';
import 'play_arrow_overlay.dart';
import 'spectator_circle_board.dart';

enum Suit { spade, heart, diamond, club, joker }

class CardWidget extends StatelessWidget {
  final int number;
  final Suit suit;
  final VoidCallback? onTap;
  final double width;
  final double height;

  const CardWidget({
    super.key,
    required this.number,
    required this.suit,
    this.onTap,
    this.width = 60,
    this.height = 90,
  });

  String get displayNumber {
    if (suit == Suit.joker) return 'JOKER';
    if (number == 11) return 'J';
    if (number == 12) return 'Q';
    if (number == 13) return 'K';
    if (number == 1) return 'A';
    return '$number';
  }

  @override
  Widget build(BuildContext context) {
    final radius = width * 0.13;
    final suitSize = width * 0.33;
    final numberSize = suit == Suit.joker ? width * 0.2 : width * 0.33;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: Colors.black, width: 1),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSuitIcon(suitSize),
            Text(
              displayNumber,
              style: TextStyle(
                fontSize: numberSize,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuitIcon(double size) {
    if (suit == Suit.joker) return Text('🤡', style: TextStyle(fontSize: size));
    String mark = {Suit.spade: '♠', Suit.heart: '♥', Suit.diamond: '♦', Suit.club: '♣'}[suit]!;
    Color color = (suit == Suit.heart || suit == Suit.diamond) ? Colors.red : Colors.black;
    return Text(mark, style: TextStyle(fontSize: size, color: color));
  }
}

/// 手札を画面幅に収めるためのカード配置サイズ
class HandCardLayout {
  final double width;
  final double height;
  final double step;

  const HandCardLayout({
    required this.width,
    required this.height,
    required this.step,
  });

  double totalWidth(int count) {
    if (count <= 0) return width;
    return width + (count - 1) * step;
  }

  /// [availableWidth] に [count] 枚の手札が収まるサイズを返す（最大7枚想定）
  static HandCardLayout compute(
    double availableWidth,
    int count, {
    double? maxWidth,
    double? minWidth,
    double gap = 8,
    double sidePadding = 12,
  }) {
    final resolvedMax = maxWidth ?? _responsiveMaxWidth(availableWidth);
    final resolvedMin = minWidth ?? (resolvedMax * 0.62).clamp(44.0, resolvedMax);

    final n = count.clamp(1, 7);
    final inner = (availableWidth - sidePadding).clamp(120.0, double.infinity);

    final widthWithGap = (inner - (n - 1) * gap) / n;
    if (widthWithGap >= resolvedMin) {
      final w = widthWithGap.clamp(resolvedMin, resolvedMax);
      return HandCardLayout(width: w, height: w * 1.5, step: w + gap);
    }

    const visibleRatio = 0.52;
    var w = inner / (1 + (n - 1) * visibleRatio);
    w = w.clamp(resolvedMin, resolvedMax);
    return HandCardLayout(width: w, height: w * 1.5, step: w * visibleRatio);
  }

  static double _responsiveMaxWidth(double availableWidth) {
    if (availableWidth >= 960) return 92;
    if (availableWidth >= 720) return 80;
    if (availableWidth >= 480) return 72;
    return (availableWidth * 0.17).clamp(54.0, 68.0);
  }

  /// 観戦用: カードを小さくし、必要なら重ねて画面内に収める
  static HandCardLayout computeSpectator(
    double availableWidth,
    int count, {
    double? maxWidth,
    double? minWidth,
    double gap = 4,
    double sidePadding = 6,
    double visibleRatio = 0.55,
  }) {
    final resolvedMax = maxWidth ?? _responsiveSpectatorMaxWidth(availableWidth);
    final resolvedMin = minWidth ?? (resolvedMax * 0.6).clamp(20.0, resolvedMax);

    final n = count.clamp(1, 7);
    final inner = (availableWidth - sidePadding).clamp(48.0, double.infinity);

    final widthWithGap = (inner - (n - 1) * gap) / n;
    if (widthWithGap >= resolvedMin) {
      final w = widthWithGap.clamp(resolvedMin, resolvedMax);
      return HandCardLayout(width: w, height: w * 1.5, step: w + gap);
    }

    var w = inner / (1 + (n - 1) * visibleRatio);
    w = w.clamp(resolvedMin, resolvedMax);
    return HandCardLayout(width: w, height: w * 1.5, step: w * visibleRatio);
  }

  static double _responsiveSpectatorMaxWidth(double availableWidth) {
    if (availableWidth >= 260) return math.min(46, availableWidth * 0.2);
    if (availableWidth >= 180) return math.min(40, availableWidth * 0.22);
    if (availableWidth >= 120) return math.min(34, availableWidth * 0.26);
    return (availableWidth * 0.3).clamp(22.0, 32.0);
  }
}

/// 裏向きのトランプ（他プレイヤーの手札枚数表示用）
class CardBackWidget extends StatelessWidget {
  final double width;
  final double height;

  const CardBackWidget({super.key, this.width = 60, this.height = 90});

  @override
  Widget build(BuildContext context) {
    final radius = width * 0.12;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1E88E5), Color(0xFF0D47A1)],
        ),
        border: Border.all(color: Colors.white70, width: 0.8),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 2, offset: Offset(1, 1)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: CustomPaint(
          painter: _CardBackPatternPainter(),
          child: Center(
            child: Icon(Icons.style, color: Colors.white.withValues(alpha: 0.3), size: width * 0.4),
          ),
        ),
      ),
    );
  }
}

class _CardBackPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final inset = size.shortestSide * 0.12;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(inset, inset, size.width - inset * 2, size.height - inset * 2),
        Radius.circular(size.shortestSide * 0.06),
      ),
      borderPaint,
    );

    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 0.8;
    const step = 6.0;
    for (double x = -size.height; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), linePaint);
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 枚数分の裏向きカードを扇状に重ねて表示
class OpponentHandVisual extends StatelessWidget {
  final int count;
  final bool isBurstWarning;
  final double cardWidth;
  final double cardHeight;
  final double overlap;

  const OpponentHandVisual({
    super.key,
    required this.count,
    this.isBurstWarning = false,
    this.cardWidth = 22,
    this.cardHeight = 33,
    this.overlap = 9,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return SizedBox(width: cardWidth, height: cardHeight);
    }

    final totalWidth = cardWidth + (count - 1) * overlap;
    return SizedBox(
      width: totalWidth,
      height: cardHeight + 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(count, (i) {
          final card = CardBackWidget(width: cardWidth, height: cardHeight);
          return Positioned(
            left: i * overlap,
            child: isBurstWarning
                ? ColorFiltered(
                    colorFilter: const ColorFilter.mode(Color(0x66FF5252), BlendMode.srcATop),
                    child: card,
                  )
                : card,
          );
        }),
      ),
    );
  }
}

/// オープンジョーカー公開の表示（文言 + 表ジョーカー1枚 + 残りは裏向き）
class OpenJokerIndicator extends StatelessWidget {
  final int handCount;
  final double cardWidth;
  final double cardHeight;
  final double overlap;
  final double fontSize;

  const OpenJokerIndicator({
    super.key,
    required this.handCount,
    this.cardWidth = 40,
    this.cardHeight = 60,
    this.overlap = 9,
    this.fontSize = 12,
  });

  @override
  Widget build(BuildContext context) {
    final backCount = (handCount - 1).clamp(0, 52);
    final totalWidth = backCount > 0 ? cardWidth + backCount * overlap : cardWidth;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'オープンジョーカー',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.yellowAccent,
            fontSize: fontSize,
            fontWeight: FontWeight.bold,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: totalWidth,
          height: cardHeight + 2,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < backCount; i++)
                Positioned(
                  left: i * overlap,
                  child: CardBackWidget(width: cardWidth, height: cardHeight),
                ),
              Positioned(
                left: backCount * overlap,
                child: CardWidget(
                  number: 0,
                  suit: Suit.joker,
                  width: cardWidth,
                  height: cardHeight,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 相手プレイヤーを半円上に配置するためのレイアウト計算
class BoardLayoutMetrics {
  final double playCardWidth;
  final double playCardHeight;
  final double deckFieldGap;
  final HandCardLayout handLayout;
  final double opponentCardWidth;
  final double moriBandHeight;
  final double moriBelowPadding;
  final double moriMessageGap;
  final double handToDeckGap;
  final double playAreaToHandGap;
  final double deckLiftGap;
  final double opponentDeckGap;
  final bool isSpectator;

  const BoardLayoutMetrics({
    required this.playCardWidth,
    required this.playCardHeight,
    required this.deckFieldGap,
    required this.handLayout,
    required this.opponentCardWidth,
    required this.moriBandHeight,
    required this.moriBelowPadding,
    required this.moriMessageGap,
    required this.handToDeckGap,
    required this.playAreaToHandGap,
    required this.deckLiftGap,
    required this.opponentDeckGap,
    required this.isSpectator,
  });

  /// 手札行・ヘッダー・枚数表示をすべて含む高さ
  double handSectionHeight({
    required bool gameStarted,
    required bool showTurnBanner,
  }) {
    const paddingV = 16.0;
    const countRow = 24.0;
    const cardToCountGap = 10.0;
    var h = paddingV + handLayout.height + cardToCountGap + countRow;
    if (gameStarted) h += 28;
    if (showTurnBanner) {
      h += 24;
    } else if (!gameStarted) {
      h += 10;
    }
    return h;
  }

  double get deckRowHalfWidth => playCardWidth + deckFieldGap / 2;

  double fieldBottomOffset({required bool showFlipButton}) {
    if (isSpectator) return 0;
    return moriBandHeight + moriBelowPadding + deckLiftGap;
  }

  double fieldHintHeight({required bool showFlipButton}) {
    final scale = (playCardHeight / 75.0).clamp(0.5, 1.0);
    var h = 16.0 * scale;
    if (showFlipButton) h += 44.0 * scale;
    return h;
  }

  double fieldBandHeight({required bool showFlipButton}) =>
      fieldHintHeight(showFlipButton: showFlipButton) + playCardHeight + 6;

  double deckBandTopY(double playAreaHeight, {required bool showFlipButton}) {
    return playAreaHeight -
        fieldBottomOffset(showFlipButton: showFlipButton) -
        fieldBandHeight(showFlipButton: showFlipButton);
  }

  double deckBandBottomY(double playAreaHeight, {required bool showFlipButton}) {
    return playAreaHeight - fieldBottomOffset(showFlipButton: showFlipButton);
  }

  double deckCenterY(
    double playAreaHeight, {
    required bool showFlipButton,
    bool lockPosition = false,
  }) {
    if (isSpectator) return playAreaHeight * 0.46;
    final fieldBottom =
        fieldBottomOffset(showFlipButton: showFlipButton) + fieldBandHeight(showFlipButton: showFlipButton);
    final bottomAnchored = playAreaHeight - fieldBottom + playCardHeight * 0.5;
    if (!lockPosition) return bottomAnchored;
    final lockedY = playAreaHeight * 0.47;
    final minY = playCardHeight + opponentDeckGap + 36;
    if (bottomAnchored > lockedY) {
      return lockedY.clamp(minY, playAreaHeight - playCardHeight);
    }
    return bottomAnchored;
  }

  double opponentBottomReserve(
    double playAreaHeight, {
    required bool showFlipButton,
    bool lockPosition = false,
  }) {
    final centerY = deckCenterY(
      playAreaHeight,
      showFlipButton: showFlipButton,
      lockPosition: lockPosition,
    );
    return playAreaHeight - centerY + playCardHeight * 0.45 + 8.0;
  }

  /// プレイエリアの高さに合わせて山札・場を縮小（対戦開始後はレイアウト固定）
  BoardLayoutMetrics adaptedForPlayHeight(
    double playH, {
    required bool showFlipButton,
    bool lockLayout = false,
  }) {
    if (isSpectator || playH <= 0 || !playH.isFinite || lockLayout) return this;

    const minOpponentZone = 36.0;
    final bottom = fieldBottomOffset(showFlipButton: showFlipButton);
    final fieldH = fieldBandHeight(showFlipButton: showFlipButton);
    final required = bottom + fieldH + minOpponentZone;
    if (playH >= required) return this;

    final scale = ((playH - bottom - minOpponentZone) / fieldH).clamp(0.48, 1.0);
    return _scaledDeck(scale);
  }

  BoardLayoutMetrics _scaledDeck(double scale) {
    final deckW = (playCardWidth * scale).clamp(26.0, playCardWidth);
    final deckH = deckW * 1.5;
    final oppW = (opponentCardWidth * scale).clamp(12.0, opponentCardWidth);

    return BoardLayoutMetrics(
      playCardWidth: deckW,
      playCardHeight: deckH,
      deckFieldGap: (deckFieldGap * scale).clamp(8.0, deckFieldGap),
      handLayout: handLayout,
      opponentCardWidth: oppW,
      moriBandHeight: moriBandHeight,
      moriBelowPadding: moriBelowPadding,
      moriMessageGap: moriMessageGap,
      handToDeckGap: (handToDeckGap * scale).clamp(10.0, handToDeckGap),
      playAreaToHandGap: playAreaToHandGap,
      deckLiftGap: (deckLiftGap * scale).clamp(4.0, deckLiftGap),
      opponentDeckGap: (opponentDeckGap * scale).clamp(10.0, opponentDeckGap),
      isSpectator: isSpectator,
    );
  }

  double moriRevealBandHeight(double width, int cardCount) {
    const outerMarginBottom = 8.0;
    const paddingVertical = 24.0;
    const titleHeight = 24.0;
    const titleGap = 8.0;
    const cardRowSlack = 4.0;
    const safety = 10.0;
    final innerWidth = width - 48;
    final layout = isSpectator
        ? HandCardLayout.computeSpectator(innerWidth, cardCount)
        : HandCardLayout.compute(
            innerWidth,
            cardCount,
            maxWidth: handLayout.width,
            minWidth: handLayout.width * 0.65,
          );
    return outerMarginBottom +
        paddingVertical +
        titleHeight +
        titleGap +
        layout.height +
        cardRowSlack +
        safety;
  }

  static double moriCountdownBandHeight(double width) {
    const sample = '🔥 もり宣言！ 残り 99 秒（もり返し受付中） 🔥';
    final lines = (sample.length * 12.0 / (width - 28)).ceil().clamp(2, 4);
    return 12 + lines * 30.0;
  }

  static BoardLayoutMetrics fromSize({
    required double width,
    required int myHandCount,
    required int opponentCount,
    required bool isSpectator,
    required bool showMoriControls,
  }) {
    final isWide = width >= 720;
    final isCompact = width < 480;
    const handSectionHorizontalPadding = 20.0;

    // 自分の手札はやや小さめ。山札・場はさらに小さく
    final handMax = isWide
        ? (width * 0.065).clamp(56.0, 84.0)
        : (width * 0.14).clamp(42.0, 58.0);
    final handLayout = HandCardLayout.compute(
      width - handSectionHorizontalPadding,
      myHandCount,
      maxWidth: handMax,
      minWidth: (handMax * 0.58).clamp(38.0, handMax),
      gap: isWide ? 10 : 7,
    );

    final deckCardW = isWide
        ? (width * 0.072).clamp(64.0, 90.0)
        : isCompact
            ? (width * 0.165).clamp(54.0, 66.0)
            : (width * 0.15).clamp(48.0, 58.0);
    final deckCardH = deckCardW * 1.5;

    var oppCW = (deckCardW * 0.44).clamp(20.0, 36.0);
    if (opponentCount >= 5) oppCW *= 0.9;
    if (opponentCount >= 7) oppCW *= 0.85;

    return BoardLayoutMetrics(
      playCardWidth: deckCardW,
      playCardHeight: deckCardH,
      deckFieldGap: (deckCardW * 0.26).clamp(12.0, 24.0),
      handLayout: handLayout,
      opponentCardWidth: oppCW,
      moriBandHeight: showMoriControls ? (isCompact ? 56.0 : 52.0) : 0,
      moriBelowPadding: isCompact ? 16.0 : 12.0,
      moriMessageGap: isCompact ? 14.0 : 10.0,
      handToDeckGap: isCompact ? 24.0 : 18.0,
      playAreaToHandGap: 0,
      deckLiftGap: isSpectator ? 0 : (isCompact ? 22.0 : 16.0),
      opponentDeckGap: isCompact ? 12.0 : 10.0,
      isSpectator: isSpectator,
    );
  }
}

class OpponentArcLayout {
  /// 山札+間隔+場の半幅（中央から端まで）
  final double deckRowHalfWidth;
  final double cardWidth;
  final double cardHeight;
  final double cardOverlap;
  final double panelWidth;
  final double panelHeight;
  final double nameFontSize;
  final double pointsFontSize;
  final double handCountFontSize;
  final Offset arcCenter;
  final double radius;
  final List<double> angles;

  const OpponentArcLayout({
    required this.deckRowHalfWidth,
    required this.cardWidth,
    required this.cardHeight,
    required this.cardOverlap,
    required this.panelWidth,
    required this.panelHeight,
    required this.nameFontSize,
    required this.pointsFontSize,
    required this.handCountFontSize,
    required this.arcCenter,
    required this.radius,
    required this.angles,
  });

  List<Offset> panelCenters() {
    return angles
        .map(
          (theta) => Offset(
            arcCenter.dx + radius * math.cos(theta),
            arcCenter.dy - radius * math.sin(theta),
          ),
        )
        .toList();
  }

  static List<double> _arcAngles(int count) {
    if (count <= 0) return const [];
    if (count == 1) return [math.pi / 2];

    // 上側の弧。山札のすぐ上に収まるようやや浅い弧を使う
    final arcStart = count <= 3 ? math.pi * 0.86 : math.pi * 0.83;
    final arcEnd = count <= 3 ? math.pi * 0.14 : math.pi * 0.17;
    return List.generate(
      count,
      (i) => arcStart - i * (arcStart - arcEnd) / (count - 1),
    );
  }

  static double _minRadiusForDeckClearance({
    required double playCardHalfH,
    required double panelH,
    required List<double> angles,
    required double clearanceGap,
  }) {
    var minR = 0.0;
    for (final theta in angles) {
      final sinT = math.sin(theta);
      if (sinT < 0.08) continue;
      final needed = (playCardHalfH + panelH / 2 + clearanceGap) / sinT;
      if (needed.isFinite && needed > 0) {
        minR = math.max(minR, needed);
      }
    }
    return minR;
  }

  static bool _panelOverlapsDeckZone({
    required Offset center,
    required double panelW,
    required double panelH,
    required double cx,
    required double deckBandTop,
    required double deckBandBottom,
    required double deckRowHalfWidth,
    required double clearanceGap,
  }) {
    final panelLeft = center.dx - panelW / 2;
    final panelRight = center.dx + panelW / 2;
    final panelTop = center.dy - panelH / 2;
    final panelBottom = center.dy + panelH / 2;

    final deckLeft = cx - deckRowHalfWidth - clearanceGap;
    final deckRight = cx + deckRowHalfWidth + clearanceGap;
    final deckTop = deckBandTop - clearanceGap;
    final deckBottom = deckBandBottom + clearanceGap;

    final hOverlap = panelLeft < deckRight && panelRight > deckLeft;
    final vOverlap = panelTop < deckBottom && panelBottom > deckTop;
    return hOverlap && vOverlap;
  }

  static double _maxRadiusForAngles({
    required double deckY,
    required double panelH,
    required List<double> angles,
    required double maxRadiusByWidth,
    required double areaHeight,
    required double bottomReserve,
    required double margin,
  }) {
    if (angles.isEmpty) return maxRadiusByWidth;

    var maxByTop = double.infinity;
    for (final theta in angles) {
      final sinT = math.sin(theta);
      if (sinT > 0.05) {
        final limit = (deckY - margin - panelH / 2) / sinT;
        maxByTop = math.min(maxByTop, limit);
      }
    }

    var maxByBottom = double.infinity;
    final bottomLimit = areaHeight - bottomReserve - panelH / 2;
    for (final theta in angles) {
      final sinT = math.sin(theta);
      if (sinT > 0.02) {
        final limit = (deckY - bottomLimit) / sinT;
        if (limit > 0) {
          maxByBottom = math.min(maxByBottom, limit);
        }
      }
    }

    var result = math.min(maxRadiusByWidth, maxByTop);
    result = math.min(result, maxByBottom);
    return math.max(result, 0);
  }

  static OpponentArcLayout compute(
    Size area,
    int count, {
    double? deckCenterY,
    double? deckZoneTopY,
    double? deckZoneBottomY,
    double bottomReserve = 58,
    double baseCardWidth = 26,
    double deckRowHalfWidth = 80,
    double deckClearanceGap = 20,
    double playCardHalfH = 28,
  }) {
    if (count <= 0) {
      final centerY = deckCenterY ?? area.height * 0.50;
      return OpponentArcLayout(
        deckRowHalfWidth: deckRowHalfWidth,
        cardWidth: baseCardWidth,
        cardHeight: baseCardWidth * 1.5,
        cardOverlap: baseCardWidth * 0.41,
        panelWidth: 0,
        panelHeight: 0,
        nameFontSize: 10,
        pointsFontSize: 11,
        handCountFontSize: 10,
        arcCenter: Offset(area.width / 2, centerY),
        radius: 0,
        angles: const [],
      );
    }

    final cx = area.width / 2;
    final deckY = deckCenterY ?? area.height * 0.50;
    const maxHandCards = 7;
    const margin = 8.0;
    final deckTop = (deckZoneTopY ?? (deckY - playCardHalfH)).clamp(margin, area.height);
    final deckBottom =
        (deckZoneBottomY ?? (deckY + playCardHalfH)).clamp(deckTop + 1, area.height);
    var minGap = count <= 3 ? 14.0 : 18.0;
    if (area.width < 400) minGap = count <= 3 ? 10.0 : 14.0;
    if (area.height < 180) minGap = math.min(minGap, 8.0);

    var scale = 1.0;
    OpponentArcLayout? best;
    var bestOverlap = double.infinity;

    for (var attempt = 0; attempt < 40; attempt++) {
      final cw = (baseCardWidth * scale).clamp(12.0, baseCardWidth);
      final ch = cw * 1.5;
      final ov = cw * 0.41;
      final handW = cw + (maxHandCards - 1) * ov;
      final panelW = handW + 10;
      final nameSize = (9.5 * scale).clamp(7.0, 10.0);
      final pointsSize = (10.5 * scale).clamp(8.0, 11.0);
      final handCountSize = (9.5 * scale).clamp(7.0, 10.0);
      final panelH = 10 + 11 + handCountSize + 4 + ch + 10;

      final angles = _arcAngles(count);
      final maxRadiusByWidth = math.max(cx - margin - panelW / 2, 0.0);
      var radius = math.min(
        maxRadiusByWidth,
        _maxRadiusForAngles(
          deckY: deckY,
          panelH: panelH,
          angles: angles,
          maxRadiusByWidth: maxRadiusByWidth,
          areaHeight: area.height,
          bottomReserve: bottomReserve,
          margin: margin,
        ),
      );

      final minRadius = _minRadiusForDeckClearance(
        playCardHalfH: playCardHalfH,
        panelH: panelH,
        angles: angles,
        clearanceGap: deckClearanceGap,
      );
      if (count >= 5 && maxRadiusByWidth > 0) {
        radius = math.max(radius, math.min(deckRowHalfWidth + panelW * 0.45, maxRadiusByWidth));
      }
      if (maxRadiusByWidth <= 0) {
        radius = 0;
      } else if (minRadius <= maxRadiusByWidth) {
        radius = radius.clamp(minRadius, maxRadiusByWidth);
      } else {
        radius = maxRadiusByWidth;
      }

      final centers = angles
          .map(
            (theta) => Offset(
              cx + radius * math.cos(theta),
              deckY - radius * math.sin(theta),
            ),
          )
          .toList();

      final layout = OpponentArcLayout(
        deckRowHalfWidth: deckRowHalfWidth,
        cardWidth: cw,
        cardHeight: ch,
        cardOverlap: ov,
        panelWidth: panelW,
        panelHeight: panelH,
        nameFontSize: nameSize,
        pointsFontSize: pointsSize,
        handCountFontSize: handCountSize,
        arcCenter: Offset(cx, deckY),
        radius: radius,
        angles: angles,
      );

      if (_layoutFits(
        area,
        centers,
        panelW,
        panelH,
        margin: margin,
        minGap: minGap,
        bottomReserve: bottomReserve,
        cx: cx,
        deckBandTop: deckTop,
        deckBandBottom: deckBottom,
        deckRowHalfWidth: deckRowHalfWidth,
        deckClearanceGap: deckClearanceGap,
      )) {
        return layout;
      }

      final overlap = _layoutOverlapScore(
        area,
        centers,
        panelW,
        panelH,
        margin: margin,
        minGap: minGap,
        bottomReserve: bottomReserve,
        cx: cx,
        deckBandTop: deckTop,
        deckBandBottom: deckBottom,
        deckRowHalfWidth: deckRowHalfWidth,
        deckClearanceGap: deckClearanceGap,
      );
      if (overlap < bestOverlap) {
        bestOverlap = overlap;
        best = layout;
      }
      scale *= 0.86;
    }

    return best ?? OpponentArcLayout(
      deckRowHalfWidth: deckRowHalfWidth,
      cardWidth: baseCardWidth.clamp(12.0, baseCardWidth),
      cardHeight: baseCardWidth.clamp(12.0, baseCardWidth) * 1.5,
      cardOverlap: baseCardWidth.clamp(12.0, baseCardWidth) * 0.41,
      panelWidth: 72,
      panelHeight: 72,
      nameFontSize: 8,
      pointsFontSize: 9,
      handCountFontSize: 8,
      arcCenter: Offset(cx, deckY),
      radius: 0,
      angles: _arcAngles(count),
    );
  }

  static double _layoutOverlapScore(
    Size area,
    List<Offset> centers,
    double panelW,
    double panelH, {
    double margin = 6,
    double minGap = 16,
    double bottomReserve = 20,
    required double cx,
    required double deckBandTop,
    required double deckBandBottom,
    required double deckRowHalfWidth,
    required double deckClearanceGap,
  }) {
    var score = 0.0;
    for (final center in centers) {
      score += math.max(margin - (center.dx - panelW / 2), 0);
      score += math.max(center.dx + panelW / 2 - (area.width - margin), 0);
      score += math.max(margin - (center.dy - panelH / 2), 0);
      score += math.max(center.dy + panelH / 2 - (area.height - bottomReserve), 0);
      if (_panelOverlapsDeckZone(
        center: center,
        panelW: panelW,
        panelH: panelH,
        cx: cx,
        deckBandTop: deckBandTop,
        deckBandBottom: deckBandBottom,
        deckRowHalfWidth: deckRowHalfWidth,
        clearanceGap: deckClearanceGap,
      )) {
        score += 1000;
      }
    }
    for (var i = 0; i < centers.length; i++) {
      for (var j = i + 1; j < centers.length; j++) {
        final dist = (centers[i] - centers[j]).distance;
        score += math.max(panelW * 0.88 + minGap - dist, 0);
      }
    }
    return score;
  }

  static bool _layoutFits(
    Size area,
    List<Offset> centers,
    double panelW,
    double panelH, {
    double margin = 6,
    double minGap = 16,
    double bottomReserve = 20,
    required double cx,
    required double deckBandTop,
    required double deckBandBottom,
    required double deckRowHalfWidth,
    required double deckClearanceGap,
  }) {
    for (final center in centers) {
      if (center.dx - panelW / 2 < margin) return false;
      if (center.dx + panelW / 2 > area.width - margin) return false;
      if (center.dy - panelH / 2 < margin) return false;
      if (center.dy + panelH / 2 > area.height - bottomReserve) return false;
      if (_panelOverlapsDeckZone(
        center: center,
        panelW: panelW,
        panelH: panelH,
        cx: cx,
        deckBandTop: deckBandTop,
        deckBandBottom: deckBandBottom,
        deckRowHalfWidth: deckRowHalfWidth,
        clearanceGap: deckClearanceGap,
      )) {
        return false;
      }
    }

    for (var i = 0; i < centers.length; i++) {
      for (var j = i + 1; j < centers.length; j++) {
        final dist = (centers[i] - centers[j]).distance;
        if (dist < panelW * 0.88 + minGap) return false;
      }
    }
    return true;
  }
}

class GameBoardView extends StatelessWidget {
  final String roomId, myId, moriPhase;
  final int fieldNumber, currentTurnIndex;
  final Suit fieldSuit;
  final List<CardWidget> myHand;
  final List<String> playerIds;
  final Map<String, String> playerNames;
  final Map<String, int> playerPoints;
  final Map<String, int> handCounts;
  final bool isHost, isInitialPhase;
  final List<String> moriDeclaredPlayerIds;
  final String? hostId, lastPlayerId, lastDrawerId, lastMoriPlayerId;
  final bool isDrawCompetitive;
  final List<CardWidget> moriRevealedHand;
  final String? moriRevealedType;
  final int playerCount;
  final int maxPlayers;
  final bool gameStarted;
  final bool isSpectator;
  final Map<String, String> spectatorNames;
  final Map<String, List<CardWidget>> allPlayerHands;
  final String matchProgressLabel;
  final int morrieRate;
  final int minMorrieBalance;
  final int? myMorrieBalance;
  final Map<String, int> playerMorrieBalances;
  final bool seriesAutoContinuing;
  final String? statusMessage;
  final int? autoPlayCountdownSeconds;
  final int? moriCountdownSeconds;
  final bool postGameVisible;
  final PostGameSummary? postGameSummary;
  final int? postGameCountdownSeconds;
  final bool awaitingGuestStayResponses;
  final int guestStayReadyCount;
  final int guestStayTotalCount;
  final int? guestCountdownSeconds;
  final bool mustRespondToStay;
  final bool canPlayAgain;
  final bool myStayResponseSubmitted;
  final VoidCallback onHostRematch;
  final VoidCallback onHostReturnToLobby;
  final VoidCallback onGuestStayInRoom;
  final VoidCallback onLeaveToLobby;
  final bool canAddBot;
  final VoidCallback? onAddBot;
  final bool hideOpponentNames;
  final VoidCallback? onToggleHideOpponentNames;
  final VoidCallback? onMorrieBalanceChanged;
  final Set<String> openJokerPlayerIds;
  final VoidCallback onMori, onDraw, onFlip, onOpenJoker;
  final Function(int) onCardTap;

  const GameBoardView({
    super.key, required this.roomId, required this.fieldNumber, required this.fieldSuit,
    required this.myHand, required this.playerIds, required this.playerNames, required this.playerPoints, required this.myId, required this.handCounts,
    required this.currentTurnIndex, required this.isHost, this.hostId, this.lastPlayerId, this.lastDrawerId,
    required this.isDrawCompetitive,
    required this.isInitialPhase, required this.moriPhase, required this.moriDeclaredPlayerIds,
    required this.playerCount,
    required this.maxPlayers,
    required this.gameStarted,
    this.isSpectator = false,
    this.spectatorNames = const {},
    this.allPlayerHands = const {},
    this.matchProgressLabel = '',
    this.morrieRate = 1,
    this.minMorrieBalance = 0,
    this.myMorrieBalance,
    this.playerMorrieBalances = const {},
    this.seriesAutoContinuing = false,
    this.statusMessage,
    this.autoPlayCountdownSeconds,
    this.moriCountdownSeconds,
    required this.postGameVisible,
    required this.postGameSummary,
    this.postGameCountdownSeconds,
    required this.awaitingGuestStayResponses,
    required this.guestStayReadyCount,
    required this.guestStayTotalCount,
    this.guestCountdownSeconds,
    required this.mustRespondToStay,
    this.canPlayAgain = true,
    required this.myStayResponseSubmitted,
    required this.onHostRematch,
    required this.onHostReturnToLobby,
    required this.onGuestStayInRoom,
    required this.onLeaveToLobby,
    this.canAddBot = false,
    this.onAddBot,
    this.hideOpponentNames = false,
    this.onToggleHideOpponentNames,
    this.onMorrieBalanceChanged,
    this.openJokerPlayerIds = const {},
    this.lastMoriPlayerId, required this.moriRevealedHand, this.moriRevealedType,
    required this.onCardTap, required this.onMori, required this.onDraw, required this.onFlip,
    required this.onOpenJoker,
  });

  @override
  Widget build(BuildContext context) {
    bool canMori;
    if (moriPhase == 'mori_declared') {
      canMori = GameRules.canDeclareMoriGaeshi(
        fieldNumber: fieldNumber,
        hand: myHand,
        moriPhase: moriPhase,
        lastMoriPlayerId: lastMoriPlayerId,
        playerId: myId,
        moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      );
    } else {
      canMori = GameRules.canDeclareMori(
        fieldNumber: fieldNumber,
        hand: myHand,
        moriPhase: moriPhase,
        lastPlayerId: lastPlayerId,
        playerId: myId,
        moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      );
    }
    bool isButtonEnabled = !isSpectator && canMori;
    final bool canOpenJoker = !isSpectator &&
        GameRules.canOpenJoker(
          hand: myHand,
          playerId: myId,
          openJokerPlayerIds: openJokerPlayerIds,
          gameStarted: gameStarted,
          moriPhase: moriPhase,
        );

    int myIdx = playerIds.indexOf(myId);
    bool isMyTurn = playerIds.isNotEmpty && (currentTurnIndex % playerIds.length == myIdx);
    final bool canDrawInCompetition = GameRules.canDrawInCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: playerIds,
      myId: myId,
      handCount: myHand.length,
    );
    bool canDraw =
        !isSpectator &&
        (isMyTurn || canDrawInCompetition) &&
        GameRules.canDraw(myHand.length, lastDrawerId, myId);
    final bool inDrawCompetition = GameRules.canPlayInDrawCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: playerIds,
      myId: myId,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSpectator
                  ? (matchProgressLabel.isNotEmpty
                      ? '観戦中 · $matchProgressLabel · ルーム: $roomId'
                      : '観戦中 · ルーム: $roomId')
                  : gameStarted
                      ? (matchProgressLabel.isNotEmpty
                          ? '$matchProgressLabel · ルーム: $roomId'
                          : 'ルーム: $roomId')
                      : (matchProgressLabel.isNotEmpty
                          ? '$matchProgressLabel · ルーム: $roomId（待機中 $playerCount/$maxPlayers人）'
                          : 'ルーム: $roomId（待機中 $playerCount/$maxPlayers人）'),
              style: const TextStyle(fontSize: 16),
            ),
            if (morrieRate > 0)
              Text(
                'レート ×$morrieRate'
                    '${minMorrieBalance > 0 ? ' · 最低 $minMorrieBalance モリー' : ''}'
                    '${!gameStarted && !isSpectator && myMorrieBalance != null ? ' · 所持 $myMorrieBalance モリー' : ''}',
                style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 12),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (isSpectator)
            TextButton.icon(
              onPressed: onLeaveToLobby,
              icon: const Icon(Icons.logout, color: Colors.white70, size: 18),
              label: const Text('退出', style: TextStyle(color: Colors.white70)),
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
        children: [
          if (isSpectator && gameStarted)
            _buildSpectatorPlayColumn()
          else
          PlayArrowOverlay(
        lastPlayerId: lastPlayerId,
        myId: myId,
        playerIds: playerIds,
        fieldNumber: fieldNumber,
        playerLabel: _playerLabel,
        builder: ({
          required fieldKey,
          required deckKey,
          required myHandKey,
          required opponentKeys,
        }) =>
            LayoutBuilder(
        builder: (context, columnConstraints) {
          final opponentCount =
              GameRules.opponentEntriesClockwiseFrom(myId, playerIds).length;
          final showFlipButton = isInitialPhase && isHost;
          final metrics = BoardLayoutMetrics.fromSize(
            width: columnConstraints.maxWidth,
            myHandCount: myHand.length,
            opponentCount: opponentCount,
            isSpectator: isSpectator,
            showMoriControls: !isSpectator,
          );
          final showTurnBanner = isMyTurn || inDrawCompetition;
          final handSectionH = metrics.handSectionHeight(
            gameStarted: gameStarted,
            showTurnBanner: showTurnBanner,
          );
          final messageBandsH = _messageBandsHeight(metrics, columnConstraints.maxWidth);
          final bottomGap =
              gameStarted && !isSpectator ? metrics.moriMessageGap : 0.0;
          final bottomReservedH = handSectionH +
              (messageBandsH > 0 ? messageBandsH + 12 : 0) +
              bottomGap;

          Widget buildMessageBands() {
            if (messageBandsH <= 0) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(
                bottom: gameStarted && !isSpectator ? metrics.moriMessageGap * 0.5 : 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isSpectator)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '観戦モード（操作不可）',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  if (moriPhase == 'mori_declared' && moriCountdownSeconds != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        moriRevealedType == 'gaeshi'
                            ? '🔥 もり返し！ 残り $moriCountdownSeconds 秒 🔥'
                            : '🔥 もり宣言！ 残り $moriCountdownSeconds 秒（もり返し受付中） 🔥',
                        textAlign: TextAlign.center,
                        softWrap: true,
                        maxLines: 4,
                        style: const TextStyle(
                          color: Colors.redAccent,
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          height: 1.35,
                        ),
                      ),
                    ),
                  if (moriPhase != 'none' &&
                      moriRevealedHand.isNotEmpty &&
                      lastMoriPlayerId != null)
                    _buildMoriRevealedHandSection(metrics, width: columnConstraints.maxWidth),
                  if (statusMessage != null) _buildStatusMessageBanner(statusMessage!),
                  if (autoPlayCountdownSeconds != null)
                    _buildAutoPlayCountdownBanner(autoPlayCountdownSeconds!),
                ],
              ),
            );
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
          if (!isSpectator && spectatorNames.isNotEmpty) _buildSpectatorNoticeBanner(),
          if (!gameStarted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.teal.shade900,
              child: Column(
                children: [
                  Text(
                    !RoomConfig.hasMinPlayers(playerCount)
                        ? 'ゲーム開始には${RoomConfig.minPlayers}人以上必要です（現在 $playerCount 人）'
                        : RoomConfig.isRoomFull(playerCount, maxPlayers)
                            ? '定員に達しました。ホストが山札をめくるとゲーム開始します'
                            : '参加者を待っています… $playerCount / $maxPlayers 人',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  if (canAddBot && onAddBot != null) ...[
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: onAddBot,
                      icon: const Icon(Icons.smart_toy_outlined, color: Colors.white70),
                      label: const Text('Botを追加', style: TextStyle(color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white54),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final playH = constraints.maxHeight;
                if (!playH.isFinite || playH <= 0) {
                  return const SizedBox.shrink();
                }
                final playMetrics = metrics.adaptedForPlayHeight(
                  playH,
                  showFlipButton: showFlipButton,
                  lockLayout: gameStarted,
                );
                final area = Size(constraints.maxWidth, playH);
                final lockDeck = gameStarted && !isSpectator;
                final deckCenterY = playMetrics.deckCenterY(
                  playH,
                  showFlipButton: showFlipButton,
                  lockPosition: lockDeck,
                );
                final bottomReserve = playMetrics.opponentBottomReserve(
                  playH,
                  showFlipButton: showFlipButton,
                  lockPosition: lockDeck,
                );

                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    if (!isSpectator)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: playMetrics.moriBelowPadding,
                        child: _buildMoriControlRow(
                          isButtonEnabled: isButtonEnabled,
                          canOpenJoker: canOpenJoker,
                        ),
                      ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: isSpectator
                          ? area.height * 0.34
                          : playMetrics.fieldBottomOffset(showFlipButton: showFlipButton),
                      child: _buildFieldArea(
                        metrics: playMetrics,
                        showFlipButton: showFlipButton,
                        isMyTurn: isMyTurn,
                        canDraw: canDraw,
                        inDrawCompetition: inDrawCompetition,
                        fieldKey: fieldKey,
                        deckKey: deckKey,
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: _buildOthersStatus(
                          opponentKeys,
                          metrics: playMetrics,
                          area: area,
                          deckCenterY: deckCenterY,
                          bottomReserve: bottomReserve,
                          showFlipButton: showFlipButton,
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          SizedBox(height: bottomReservedH),
                ],
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    buildMessageBands(),
                    SizedBox(
                      height: handSectionH,
                      child: KeyedSubtree(
                        key: myHandKey,
                        child: _buildMyHandSection(
                          metrics,
                          isMyTurn,
                          inDrawCompetition: inDrawCompetition,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
          ),
          if (postGameVisible)
            PostGameOverlay(
              summary: postGameSummary,
              isHost: isHost,
              isSpectator: isSpectator,
              countdownSeconds: postGameCountdownSeconds,
              seriesAutoContinuing: seriesAutoContinuing,
              awaitingGuestStayResponses: awaitingGuestStayResponses,
              guestStayReadyCount: guestStayReadyCount,
              guestStayTotalCount: guestStayTotalCount,
              guestCountdownSeconds: guestCountdownSeconds,
              mustRespondToStay: mustRespondToStay,
              canPlayAgain: canPlayAgain,
              minMorrieBalance: minMorrieBalance,
              myStayResponseSubmitted: myStayResponseSubmitted,
              onHostRematch: onHostRematch,
              onHostReturnToLobby: onHostReturnToLobby,
              onGuestStayInRoom: onGuestStayInRoom,
              onLeaveToLobby: onLeaveToLobby,
            ),
        ],
      ),
          ),
          _buildSideBar(context),
        ],
      ),
    );
  }

  double _messageBandsHeight(BoardLayoutMetrics metrics, double width) {
    var h = 0.0;
    if (isSpectator) h += 22;
    if (moriPhase == 'mori_declared' && moriCountdownSeconds != null) {
      h += BoardLayoutMetrics.moriCountdownBandHeight(width);
    }
    if (moriPhase != 'none' && moriRevealedHand.isNotEmpty && lastMoriPlayerId != null) {
      h += metrics.moriRevealBandHeight(width, moriRevealedHand.length);
    }
    if (statusMessage != null) {
      h += _estimateStatusBannerHeight(statusMessage!, width);
    }
    if (autoPlayCountdownSeconds != null) h += 56;
    return h;
  }

  double _estimateStatusBannerHeight(String message, double width) {
    final charsPerLine = ((width - 72) / 13).floor().clamp(12, 40);
    final lines = (message.length / charsPerLine).ceil().clamp(1, 5);
    return 10 + 22 + lines * 21.0;
  }

  Widget _buildSpectatorPlayColumn() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
      children: [
        if (spectatorNames.isNotEmpty) _buildSpectatorNoticeBanner(),
        Expanded(
          child: SpectatorCircleBoard(
            playerIds: playerIds,
            allPlayerHands: allPlayerHands,
            playerPoints: playerPoints,
            openJokerPlayerIds: openJokerPlayerIds,
            fieldNumber: fieldNumber,
            fieldSuit: fieldSuit,
            lastPlayerId: lastPlayerId,
            currentTurnIndex: currentTurnIndex,
            lastDrawerId: lastDrawerId,
            isDrawCompetitive: isDrawCompetitive,
            isInitialPhase: isInitialPhase,
            gameStarted: gameStarted,
            playerLabel: _playerLabel,
          ),
        ),
        if (moriPhase == 'mori_declared' && moriCountdownSeconds != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              moriRevealedType == 'gaeshi'
                  ? '🔥 もり返し！ 残り $moriCountdownSeconds 秒 🔥'
                  : '🔥 もり宣言！ 残り $moriCountdownSeconds 秒（もり返し受付中） 🔥',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        if (moriPhase != 'none' && moriRevealedHand.isNotEmpty && lastMoriPlayerId != null)
          _buildMoriRevealedHandSection(null, width: constraints.maxWidth),
        if (statusMessage != null) _buildStatusMessageBanner(statusMessage!),
        if (autoPlayCountdownSeconds != null) _buildAutoPlayCountdownBanner(autoPlayCountdownSeconds!),
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(
            '観戦モード（操作不可）',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
          ),
        ),
      ],
    );
      },
    );
  }

  Widget _buildSpectatorNoticeBanner() {
    final count = spectatorNames.length;
    final message = hideOpponentNames
        ? '観戦者が $count 人います'
        : () {
            final labels = spectatorNames.values.where((n) => n.isNotEmpty).join('、');
            return labels.isNotEmpty
                ? '観戦中: $labels（$count人）'
                : '観戦者が $count 人います';
          }();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.indigo.shade900.withValues(alpha: 0.95),
      child: Row(
        children: [
          const Icon(Icons.visibility, color: Colors.lightBlueAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSideBar(BuildContext context) {
    return AppSideBar(
      hideOpponentNames: hideOpponentNames,
      onToggleHideOpponentNames: onToggleHideOpponentNames,
      items: const [],
    );
  }

  Widget _buildMoriRevealedHandSection(BoardLayoutMetrics? metrics, {required double width}) {
    final declarerLabel = _playerLabel(lastMoriPlayerId);
    final declarationLabel = moriRevealedType == 'gaeshi' ? 'もり返し' : 'もり';
    final innerWidth = width - 48;
    final layout = isSpectator
        ? HandCardLayout.computeSpectator(innerWidth, moriRevealedHand.length)
        : HandCardLayout.compute(
            innerWidth,
            moriRevealedHand.length,
            maxWidth: metrics?.handLayout.width,
            minWidth: metrics != null ? metrics.handLayout.width * 0.65 : null,
          );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purpleAccent, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$declarerLabel の手札（$declarationLabel 宣言）',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: layout.height,
            width: double.infinity,
            child: Center(
              child: _buildOverlappingHandRow(
                cards: moriRevealedHand,
                layout: layout,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _playerLabel(String? playerId) {
    return PlayerDisplayName.resolve(
      playerId: playerId,
      playerIds: playerIds,
      myId: myId,
      playerNames: playerNames,
      hostId: hostId,
      hideOpponentNames: hideOpponentNames,
    );
  }

  Widget _buildMoriControlRow({
    required bool isButtonEnabled,
    required bool canOpenJoker,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (canOpenJoker)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton(
              onPressed: onOpenJoker,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.yellowAccent,
                side: const BorderSide(color: Colors.yellowAccent),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: const Text('オープンジョーカー'),
            ),
          ),
        ElevatedButton(
          onPressed: isButtonEnabled ? onMori : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: moriPhase == 'mori_declared' ? Colors.red : Colors.orange,
            disabledBackgroundColor: Colors.grey[700],
            padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 12),
          ),
          child: Text(
            moriPhase == 'mori_declared' ? 'もり返し！！' : 'もり！',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: isButtonEnabled ? Colors.white : Colors.white38,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFieldArea({
    required BoardLayoutMetrics metrics,
    required bool showFlipButton,
    required bool isMyTurn,
    required bool canDraw,
    required bool inDrawCompetition,
    required GlobalKey fieldKey,
    required GlobalKey deckKey,
  }) {
    final cardW = metrics.playCardWidth;
    final cardH = metrics.playCardHeight;
    final gap = metrics.deckFieldGap;

    return Column(children: [
      if (showFlipButton)
        Padding(
          padding: EdgeInsets.only(bottom: 12 * (cardH / 75.0).clamp(0.5, 1.0)),
          child: ElevatedButton(
            onPressed: RoomConfig.hasMinPlayers(playerCount) ? onFlip : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.yellow[900],
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: (10 * (cardH / 75.0).clamp(0.5, 1.0)).clamp(6.0, 10.0),
              ),
            ),
            child: Text(
              '山札をめくる',
              style: TextStyle(
                color: Colors.white,
                fontSize: (14 * (cardH / 75.0).clamp(0.5, 1.0)).clamp(11.0, 14.0),
              ),
            ),
          ),
        ),
      if (GameRules.isJokerOnField(fieldNumber, fieldSuit))
        const Text("🃏 ジョーカー！誰でも出せます！", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
      if (isInitialPhase && fieldNumber != -1 && !GameRules.isJokerOnField(fieldNumber, fieldSuit))
        const Text("同じ数字なら誰でも出せます（早い者勝ち）", style: TextStyle(color: Colors.white70, fontSize: 10)),
      if (inDrawCompetition)
        const Text(
          '⚡ ドロー直後！出すか引くか早い者勝ち',
          style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12),
        ),
      if (!isMyTurn &&
          !inDrawCompetition &&
          !isInitialPhase &&
          !GameRules.isJokerOnField(fieldNumber, fieldSuit) &&
          fieldNumber != -1 &&
          moriPhase == 'none')
        const Text("同じ数字なら割り込み可能", style: TextStyle(color: Colors.white70, fontSize: 10)),
      const SizedBox(height: 6),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(
          onTap: (canDraw && !isInitialPhase && moriPhase == 'none') ? onDraw : null,
          child: Container(
            key: deckKey,
            width: cardW,
            height: cardH,
            decoration: BoxDecoration(
              color: canDraw ? Colors.blueGrey[800] : Colors.grey[900],
              borderRadius: BorderRadius.circular(cardW * 0.13),
              border: Border.all(color: canDraw ? Colors.yellow : Colors.white24),
            ),
            child: Icon(Icons.help_outline, color: Colors.white24, size: cardW * 0.45),
          ),
        ),
        SizedBox(width: gap),
        fieldNumber == -1
            ? Container(
                width: cardW,
                height: cardH,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(cardW * 0.13),
                ),
              )
            : KeyedSubtree(
                key: fieldKey,
                child: CardWidget(
                  suit: fieldSuit,
                  number: fieldNumber,
                  width: cardW,
                  height: cardH,
                ),
              ),
      ]),
    ]);
  }

  Widget _buildOthersStatus(
    Map<String, GlobalKey> opponentKeys, {
    required BoardLayoutMetrics metrics,
    required Size area,
    required double deckCenterY,
    required double bottomReserve,
    required bool showFlipButton,
  }) {
    final others = GameRules.opponentEntriesClockwiseFrom(myId, playerIds);
    if (others.isEmpty) return const SizedBox.shrink();

    final layout = OpponentArcLayout.compute(
      area,
      others.length,
      deckCenterY: deckCenterY,
      deckZoneTopY: showFlipButton
          ? metrics.deckBandTopY(area.height, showFlipButton: true)
          : deckCenterY - metrics.playCardHeight / 2,
      deckZoneBottomY: showFlipButton
          ? metrics.deckBandBottomY(area.height, showFlipButton: true)
          : deckCenterY + metrics.playCardHeight / 2,
      bottomReserve: bottomReserve,
      baseCardWidth: metrics.opponentCardWidth,
      deckRowHalfWidth: metrics.deckRowHalfWidth,
      deckClearanceGap: metrics.opponentDeckGap,
      playCardHalfH: metrics.playCardHeight / 2,
    );
    final centers = layout.panelCenters();

    return Stack(
      clipBehavior: Clip.hardEdge,
      children: List.generate(others.length, (i) {
        final entry = others[i];
        final playerId = entry.value;
        final handCount = handCounts[playerId] ?? 0;
        final hasDrawRight = GameRules.hasDrawPrivilege(
          playerId: playerId,
          playerIds: playerIds,
          turnIndex: currentTurnIndex,
          isDrawCompetitive: isDrawCompetitive,
          lastDrawerId: lastDrawerId,
          lastPlayerId: lastPlayerId,
          isInitialPhase: isInitialPhase,
          fieldNumber: fieldNumber,
          handCount: handCount,
        );
        final isBurstWarning = handCount >= 6;
        final hasOpenJoker = openJokerPlayerIds.contains(playerId);
        final center = centers[i];
        final left = (center.dx - layout.panelWidth / 2)
            .clamp(0.0, math.max(0.0, area.width - layout.panelWidth))
            .toDouble();
        final top = (center.dy - layout.panelHeight / 2)
            .clamp(0.0, math.max(0.0, area.height - layout.panelHeight))
            .toDouble();

        return Positioned(
          left: left,
          top: top,
          width: layout.panelWidth,
          child: _buildOpponentPanel(
            key: opponentKeys[playerId],
            playerId: playerId,
            handCount: handCount,
            hasDrawRight: hasDrawRight,
            isBurstWarning: isBurstWarning,
            hasOpenJoker: hasOpenJoker,
            layout: layout,
          ),
        );
      }),
    );
  }

  Widget _buildOpponentPanel({
    required Key? key,
    required String playerId,
    required int handCount,
    required bool hasDrawRight,
    required bool isBurstWarning,
    required bool hasOpenJoker,
    required OpponentArcLayout layout,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: hasDrawRight ? Colors.orange.withValues(alpha: 0.2) : Colors.black26,
        border: hasDrawRight
            ? Border.all(color: Colors.orangeAccent, width: 2)
            : Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _playerLabel(playerId),
            style: TextStyle(color: Colors.white70, fontSize: layout.nameFontSize),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (gameStarted)
            Text(
              '${playerPoints[playerId] ?? 0}点',
              style: TextStyle(
                color: (playerPoints[playerId] ?? 0) >= 0 ? Colors.amberAccent : Colors.redAccent,
                fontSize: layout.pointsFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          if (gameStarted && morrieRate > 0 && playerMorrieBalances[playerId] != null)
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.paid,
                    color: Colors.lightGreenAccent,
                    size: layout.pointsFontSize + 1,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '${playerMorrieBalances[playerId]}',
                    style: TextStyle(
                      color: Colors.lightGreenAccent,
                      fontSize: layout.pointsFontSize,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 2),
          if (hasOpenJoker)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: OpenJokerIndicator(
                handCount: handCount,
                cardWidth: layout.cardWidth,
                cardHeight: layout.cardHeight,
                overlap: layout.cardOverlap,
                fontSize: layout.handCountFontSize,
              ),
            )
          else
            OpponentHandVisual(
              count: handCount,
              isBurstWarning: isBurstWarning,
              cardWidth: layout.cardWidth,
              cardHeight: layout.cardHeight,
              overlap: layout.cardOverlap,
            ),
          const SizedBox(height: 2),
          Text(
            '$handCount枚',
            style: TextStyle(
              color: isBurstWarning ? Colors.red : Colors.white70,
              fontSize: layout.handCountFontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAutoPlayCountdownBanner(int seconds) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.lightBlueAccent, width: 1),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.timer_outlined, color: Colors.lightBlueAccent, size: 18),
          const SizedBox(width: 8),
          Text(
            'あと $seconds 秒で自動操作',
            style: const TextStyle(
              color: Colors.lightBlueAccent,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusMessageBanner(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amberAccent, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.amberAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlappingHandRow({
    required List<CardWidget> cards,
    required HandCardLayout layout,
    void Function(int index)? onTap,
  }) {
    if (cards.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: layout.totalWidth(cards.length),
      height: layout.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: List.generate(cards.length, (i) {
          return Positioned(
            left: i * layout.step,
            child: CardWidget(
              width: layout.width,
              height: layout.height,
              number: cards[i].number,
              suit: cards[i].suit,
              onTap: onTap != null ? () => onTap(i) : null,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildMyHandSection(
    BoardLayoutMetrics metrics,
    bool isMyTurn, {
    required bool inDrawCompetition,
  }) {
    final isBurstWarning = myHand.length >= 6;
    final layout = metrics.handLayout;
    final showTurnBanner = isMyTurn || inDrawCompetition;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(color: Colors.black26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showTurnBanner)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '${isMyTurn ? '（あなたのターン）' : ''}${inDrawCompetition ? ' · ドロー競合中' : ''}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
          if (gameStarted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '累計 ${playerPoints[myId] ?? 0}点',
                    style: TextStyle(
                      color: (playerPoints[myId] ?? 0) >= 0
                          ? Colors.amberAccent
                          : Colors.redAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (morrieRate > 0 && myMorrieBalance != null) ...[
                    const Text(
                      ' · ',
                      style: TextStyle(color: Colors.white54, fontSize: 13),
                    ),
                    const Icon(Icons.paid, color: Colors.lightGreenAccent, size: 15),
                    const SizedBox(width: 3),
                    Text(
                      '所持 $myMorrieBalance',
                      style: const TextStyle(
                        color: Colors.lightGreenAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            const SizedBox(height: 6),
          SizedBox(
            height: layout.height,
            width: double.infinity,
            child: Center(
              child: ClipRect(
                child: _buildOverlappingHandRow(
                  cards: myHand,
                  layout: layout,
                  onTap: onCardTap,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${myHand.length}枚',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isBurstWarning ? Colors.red : Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

/// ゲーム終了後の再戦・退室UI
class PostGameOverlay extends StatelessWidget {
  final PostGameSummary? summary;
  final bool isHost;
  final bool isSpectator;
  final int? countdownSeconds;
  final bool seriesAutoContinuing;
  final bool awaitingGuestStayResponses;
  final int guestStayReadyCount;
  final int guestStayTotalCount;
  final int? guestCountdownSeconds;
  final bool mustRespondToStay;
  final bool canPlayAgain;
  final int minMorrieBalance;
  final bool myStayResponseSubmitted;
  final VoidCallback onHostRematch;
  final VoidCallback onHostReturnToLobby;
  final VoidCallback onGuestStayInRoom;
  final VoidCallback onLeaveToLobby;

  const PostGameOverlay({
    super.key,
    required this.summary,
    required this.isHost,
    this.isSpectator = false,
    this.countdownSeconds,
    this.seriesAutoContinuing = false,
    required this.awaitingGuestStayResponses,
    required this.guestStayReadyCount,
    required this.guestStayTotalCount,
    this.guestCountdownSeconds,
    required this.mustRespondToStay,
    this.canPlayAgain = true,
    this.minMorrieBalance = 0,
    required this.myStayResponseSubmitted,
    required this.onHostRematch,
    required this.onHostReturnToLobby,
    required this.onGuestStayInRoom,
    required this.onLeaveToLobby,
  });

  String _formatDelta(int? delta) {
    if (delta == null || delta == 0) return '±0';
    return delta > 0 ? '+$delta' : '$delta';
  }

  Widget _buildResultBanner({
    required String label,
    required String message,
    required Color accent,
    required Color background,
    required IconData icon,
    required double bodySize,
    required double headerSize,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent, width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: accent, size: headerSize + 4),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: accent,
                    fontSize: headerSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: bodySize,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _subtitle() {
    if (isSpectator) return '観戦を終了する場合はロビーへ戻ってください';
    if (seriesAutoContinuing) return 'カウントダウン後、ホストが山札をめくると次の対戦が始まります';
    if (awaitingGuestStayResponses) {
      if (isHost) return '参加者の回答: $guestStayReadyCount / $guestStayTotalCount 人';
      if (mustRespondToStay) return 'ルームに残りますか？';
      if (!canPlayAgain && minMorrieBalance > 0) {
        return '最低入室モリー $minMorrieBalance 未満のため再戦できません';
      }
      if (myStayResponseSubmitted) return '回答済み。他のプレイヤーを待っています…';
      return 'ホストの選択を待っています…';
    }
    if (isHost) {
      if (!canPlayAgain && minMorrieBalance > 0) {
        return '最低入室モリー $minMorrieBalance 未満のため再戦できません';
      }
      return 'もう一度遊ぶ / ロビーへ';
    }
    return 'ホストの選択を待っています…';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final cardWidth = (size.width * 0.94).clamp(280.0, 520.0);
    final maxCardHeight = size.height * 0.88 - media.padding.vertical;
    final maxTableHeight = (maxCardHeight * 0.42).clamp(120.0, 240.0);
    final titleSize = (size.width / 24).clamp(16.0, 20.0);
    final bodySize = (size.width / 28).clamp(12.0, 15.0);
    final headerSize = (size.width / 32).clamp(11.0, 13.0);

    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.72),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: cardWidth,
                maxHeight: maxCardHeight,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF1B3A1B),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orangeAccent, width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          summary?.title ?? '試合結果',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: titleSize,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (summary?.cardBurstMessage != null) ...[
                          const SizedBox(height: 10),
                          _buildResultBanner(
                            label: 'バースト',
                            message: summary!.cardBurstMessage!,
                            accent: Colors.redAccent,
                            background: Colors.red.withValues(alpha: 0.2),
                            icon: Icons.warning_amber_rounded,
                            bodySize: bodySize,
                            headerSize: headerSize,
                          ),
                        ],
                        if (summary?.morrieBurstMessage != null) ...[
                          const SizedBox(height: 10),
                          _buildResultBanner(
                            label: '飛び',
                            message: summary!.morrieBurstMessage!,
                            accent: Colors.deepOrangeAccent,
                            background: Colors.deepOrange.withValues(alpha: 0.22),
                            icon: Icons.trending_down,
                            bodySize: bodySize,
                            headerSize: headerSize,
                          ),
                        ],
                        const SizedBox(height: 12),
                        _buildResultsTable(
                          bodySize,
                          headerSize,
                          maxHeight: maxTableHeight,
                        ),
                        if (summary?.showsRecoveredMorrieBalance == true) ...[
                          const SizedBox(height: 6),
                          Text(
                            '※ Botの残高は飛び後の回復モリー（+${MorrieRules.burstRecoveryAmount}）を含みます',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: headerSize * 0.9,
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          _subtitle(),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white70, fontSize: headerSize),
                        ),
                        if (seriesAutoContinuing && countdownSeconds != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '残り $countdownSeconds 秒で次の対戦',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: bodySize,
                            ),
                          ),
                        ],
                        if (isHost &&
                            !awaitingGuestStayResponses &&
                            !seriesAutoContinuing &&
                            countdownSeconds != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '残り $countdownSeconds 秒（未選択でルーム閉鎖）',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: bodySize,
                            ),
                          ),
                        ],
                        if (awaitingGuestStayResponses && guestCountdownSeconds != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            '残り $guestCountdownSeconds 秒（未回答は自動退室）',
                            style: TextStyle(
                              color: Colors.amberAccent,
                              fontWeight: FontWeight.bold,
                              fontSize: bodySize,
                            ),
                          ),
                        ],
                        const SizedBox(height: 14),
                        if (seriesAutoContinuing)
                          Text(
                            'カウントダウン後、ホストが山札をめくると次の対戦が始まります',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white54, fontSize: headerSize),
                          )
                        else if (isSpectator)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: onLeaveToLobby,
                              child: const Text('ロビーへ'),
                            ),
                          )
                        else if (awaitingGuestStayResponses) ...[
                          if (isHost)
                            Text(
                              '全員の回答が揃うとルームを公開します',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: headerSize),
                            )
                          else if (mustRespondToStay) ...[
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: onGuestStayInRoom,
                                child: const Text('ルームに残る'),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: onLeaveToLobby,
                                child: const Text('ロビーへ'),
                              ),
                            ),
                          ] else if (!canPlayAgain && minMorrieBalance > 0) ...[
                            Text(
                              '最低入室モリー $minMorrieBalance 未満のため、もう一度遊ぶを選べません',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.redAccent, fontSize: bodySize),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: onLeaveToLobby,
                                child: const Text('ロビーへ'),
                              ),
                            ),
                          ] else
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: onLeaveToLobby,
                                child: const Text('ロビーへ'),
                              ),
                            ),
                        ] else if (isHost) ...[
                          if (canPlayAgain)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: onHostRematch,
                                child: const Text('もう一度遊ぶ'),
                              ),
                            )
                          else if (minMorrieBalance > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                '最低入室モリー $minMorrieBalance 未満のため、もう一度遊ぶを選べません',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.redAccent, fontSize: bodySize),
                              ),
                            ),
                          if (canPlayAgain) const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: onHostReturnToLobby,
                              child: const Text('ロビーへ（ルームを閉鎖）'),
                            ),
                          ),
                        ] else
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: onLeaveToLobby,
                              child: const Text('ロビーへ'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultsTable(
    double bodySize,
    double headerSize, {
    required double maxHeight,
  }) {
    final players = summary?.players ?? [];
    final showRating = summary?.showRating ?? false;
    final showMorrie = summary?.showMorrie ?? false;
    final showsRecoveredMorrieBalance =
        summary?.showsRecoveredMorrieBalance ?? false;

    if (players.isEmpty) {
      return Text(
        '結果を読み込み中…',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54, fontSize: bodySize),
      );
    }

    const colRank = 40.0;
    const colName = 88.0;
    const colMatch = 52.0;
    const colTotal = 52.0;
    const colMorrieDelta = 60.0;
    const colMorrieBalance = 80.0;
    const colRating = 96.0;
    const rowHeight = 34.0;

    final headers = <String>[
      '順位',
      '名前',
      '今回',
      '累計',
      if (showMorrie) 'モリー',
      if (showMorrie) showsRecoveredMorrieBalance ? '残高(回復後)' : '残高',
      if (showRating) 'レート',
    ];
    final widths = <double>[
      colRank,
      colName,
      colMatch,
      colTotal,
      if (showMorrie) colMorrieDelta,
      if (showMorrie) colMorrieBalance,
      if (showRating) colRating,
    ];

    final tableHeight = rowHeight * (players.length + 1) + 4;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                height: tableHeight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _resultTableRow(
                      widths: widths,
                      height: rowHeight,
                      cells: headers,
                      fontSize: headerSize,
                      isHeader: true,
                    ),
                    for (final row in players)
                      _resultTableRow(
                        widths: widths,
                        height: rowHeight,
                        fontSize: bodySize,
                        cells: [
                          '${row.rank}',
                          row.name,
                          _formatDelta(row.matchDelta),
                          '${row.totalPoints}',
                          if (showMorrie)
                            row.morrieDelta != null ? _formatDelta(row.morrieDelta) : '0',
                          if (showMorrie)
                            row.morrieBalance != null
                                ? (row.morrieBalanceIsRecovered
                                    ? '${row.morrieBalance}※'
                                    : '${row.morrieBalance}')
                                : '—',
                          if (showRating)
                            row.rating != null
                                ? '${row.rating} (${_formatDelta(row.ratingDelta)})'
                                : '—',
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _resultTableRow({
    required List<double> widths,
    required double height,
    required List<String> cells,
    required double fontSize,
    bool isHeader = false,
  }) {
    assert(widths.length == cells.length);
    final color = isHeader ? Colors.white70 : Colors.white;
    final weight = isHeader ? FontWeight.bold : FontWeight.normal;
    final border = isHeader
        ? const Border(bottom: BorderSide(color: Colors.white24))
        : null;

    return Container(
      height: height,
      decoration: BoxDecoration(border: border),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            SizedBox(
              width: widths[i],
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Align(
                  alignment: i == 1 ? Alignment.centerLeft : Alignment.center,
                  child: Text(
                    cells[i],
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: fontSize,
                      fontWeight: weight,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}