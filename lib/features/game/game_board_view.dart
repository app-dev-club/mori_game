import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../../logic/bot_logic.dart';
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
  static HandCardLayout compute(double availableWidth, int count) {
    const maxWidth = 60.0;
    const minWidth = 34.0;
    const gap = 6.0;
    const sidePadding = 12.0;

    final n = count.clamp(1, 7);
    final inner = (availableWidth - sidePadding).clamp(120.0, double.infinity);

    final widthWithGap = (inner - (n - 1) * gap) / n;
    if (widthWithGap >= minWidth) {
      final w = widthWithGap.clamp(minWidth, maxWidth);
      return HandCardLayout(width: w, height: w * 1.5, step: w + gap);
    }

    const visibleRatio = 0.5;
    var w = inner / (1 + (n - 1) * visibleRatio);
    w = w.clamp(minWidth, maxWidth);
    return HandCardLayout(width: w, height: w * 1.5, step: w * visibleRatio);
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
class OpponentArcLayout {
  /// [_buildFieldArea] の山札+間隔+場の半幅（中央から端まで）
  static const double deckRowHalfWidth = 70;

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

  static OpponentArcLayout compute(Size area, int count, {double? deckCenterY}) {
    if (count <= 0) {
      final centerY = deckCenterY ?? area.height * 0.50;
      return OpponentArcLayout(
        cardWidth: 22,
        cardHeight: 33,
        cardOverlap: 9,
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
    const margin = 6.0;
    const minGap = 16.0;
    const bottomReserve = 20.0;

    var scale = 1.0;
    OpponentArcLayout? best;

    for (var attempt = 0; attempt < 32; attempt++) {
      final cw = (22.0 * scale).clamp(8.0, 22.0);
      final ch = cw * 1.5;
      final ov = cw * 0.41;
      final handW = cw + (maxHandCards - 1) * ov;
      final panelW = handW + 10;
      final nameSize = (9.5 * scale).clamp(7.0, 10.0);
      final pointsSize = (10.5 * scale).clamp(8.0, 11.0);
      final handCountSize = (9.5 * scale).clamp(7.0, 10.0);
      final panelH = 10 + 11 + handCountSize + 4 + ch + 10;

      final angleInset = count >= 5 ? 0.06 : 0.03;
      final angles = count == 1
          ? [math.pi / 2]
          : List.generate(
              count,
              (i) =>
                  math.pi -
                  angleInset -
                  i * (math.pi - angleInset * 2) / (count - 1),
            );

      final maxRadiusByWidth = cx - margin - panelW / 2;
      var radius = math.max(
        deckRowHalfWidth + panelW * 0.65 + 28,
        maxRadiusByWidth * (count >= 4 ? 0.97 : 0.90),
      );
      radius += (count - 1) * 8.0;
      radius = radius.clamp(deckRowHalfWidth + panelW * 0.5, maxRadiusByWidth);

      if (count > 2) {
        final topAtMid = deckY - radius;
        final minTop = panelH * 0.5 + 10;
        if (topAtMid < minTop) {
          radius = math.min(radius, deckY - minTop);
        }
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
      )) {
        return layout;
      }
      best = layout;
      scale *= 0.86;
    }

    return best!;
  }

  static bool _layoutFits(
    Size area,
    List<Offset> centers,
    double panelW,
    double panelH, {
    double margin = 6,
    double minGap = 16,
    double bottomReserve = 20,
  }) {
    for (final center in centers) {
      if (center.dx - panelW / 2 < margin) return false;
      if (center.dx + panelW / 2 > area.width - margin) return false;
      if (center.dy - panelH / 2 < margin) return false;
      if (center.dy + panelH / 2 > area.height - bottomReserve) return false;
    }

    for (var i = 0; i < centers.length - 1; i++) {
      final dist = (centers[i] - centers[i + 1]).distance;
      if (dist < panelW * 0.78 + minGap) return false;
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
  final int? myMorrieBalance;
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
  final bool myStayResponseSubmitted;
  final VoidCallback onHostRematch;
  final VoidCallback onHostReturnToLobby;
  final VoidCallback onGuestStayInRoom;
  final VoidCallback onLeaveToLobby;
  final bool canAddBot;
  final VoidCallback? onAddBot;
  final bool hideOpponentNames;
  final VoidCallback? onToggleHideOpponentNames;
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
    this.myMorrieBalance,
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
    required this.myStayResponseSubmitted,
    required this.onHostRematch,
    required this.onHostReturnToLobby,
    required this.onGuestStayInRoom,
    required this.onLeaveToLobby,
    this.canAddBot = false,
    this.onAddBot,
    this.hideOpponentNames = false,
    this.onToggleHideOpponentNames,
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
                    '${myMorrieBalance != null ? ' · 所持 $myMorrieBalance モリー' : ''}',
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
            Column(
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
            flex: 4,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final deckCenterY = constraints.maxHeight * 0.50;
                final playArea = Size(constraints.maxWidth, constraints.maxHeight);
                return Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Positioned.fill(
                      child: _buildOthersStatus(
                        opponentKeys,
                        area: playArea,
                        deckCenterY: deckCenterY,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (deckCenterY - 72).clamp(0.0, constraints.maxHeight - 130),
                      child: _buildFieldArea(
                        isMyTurn: isMyTurn,
                        canDraw: canDraw,
                        inDrawCompetition: inDrawCompetition,
                        fieldKey: fieldKey,
                        deckKey: deckKey,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (!isSpectator)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
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
                    padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
                  ),
                  child: Text(
                    moriPhase == 'mori_declared' ? "もり返し！！" : "もり！",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: isButtonEnabled ? Colors.white : Colors.white38,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isSpectator)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Text(
                '観戦モード（操作不可）',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
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
            _buildMoriRevealedHandSection(),
          if (statusMessage != null) _buildStatusMessageBanner(statusMessage!),
          if (autoPlayCountdownSeconds != null) _buildAutoPlayCountdownBanner(autoPlayCountdownSeconds!),
          KeyedSubtree(
            key: myHandKey,
            child: _buildMyHandSection(isMyTurn, inDrawCompetition: inDrawCompetition),
          ),
        ],
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
              myStayResponseSubmitted: myStayResponseSubmitted,
              onHostRematch: onHostRematch,
              onHostReturnToLobby: onHostReturnToLobby,
              onGuestStayInRoom: onGuestStayInRoom,
              onLeaveToLobby: onLeaveToLobby,
            ),
        ],
      ),
          ),
          _buildSideBar(),
        ],
      ),
    );
  }

  Widget _buildSpectatorPlayColumn() {
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
          _buildMoriRevealedHandSection(),
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

  Widget _buildSideBar() {
    return AppSideBar(
      hideOpponentNames: hideOpponentNames,
      onToggleHideOpponentNames: onToggleHideOpponentNames,
    );
  }

  Widget _buildMoriRevealedHandSection() {
    final declarerLabel = _playerLabel(lastMoriPlayerId);
    final declarationLabel = moriRevealedType == 'gaeshi' ? 'もり返し' : 'もり';
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$declarerLabel の手札（$declarationLabel 宣言）',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final layout = HandCardLayout.compute(
                constraints.maxWidth,
                moriRevealedHand.length,
              );
              return SizedBox(
                height: layout.height + 4,
                width: double.infinity,
                child: Center(
                  child: _buildOverlappingHandRow(
                    cards: moriRevealedHand,
                    layout: layout,
                  ),
                ),
              );
            },
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

  Widget _buildFieldArea({
    required bool isMyTurn,
    required bool canDraw,
    required bool inDrawCompetition,
    required GlobalKey fieldKey,
    required GlobalKey deckKey,
  }) {
    return Column(children: [
      if (isInitialPhase && isHost)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ElevatedButton(
            onPressed: RoomConfig.hasMinPlayers(playerCount) ? onFlip : null,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[900]),
            child: const Text('山札をめくる', style: TextStyle(color: Colors.white)),
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
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(
          onTap: (canDraw && !isInitialPhase && moriPhase == 'none') ? onDraw : null,
          child: Container(
            key: deckKey,
            width: 60, height: 90,
            decoration: BoxDecoration(
              color: canDraw ? Colors.blueGrey[800] : Colors.grey[900],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: canDraw ? Colors.yellow : Colors.white24),
            ),
            child: const Icon(Icons.help_outline, color: Colors.white24),
          ),
        ),
        const SizedBox(width: 20),
        fieldNumber == -1
            ? Container(width: 60, height: 90, decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)))
            : KeyedSubtree(
                key: fieldKey,
                child: CardWidget(suit: fieldSuit, number: fieldNumber),
              ),
      ]),
    ]);
  }

  Widget _buildOthersStatus(
    Map<String, GlobalKey> opponentKeys, {
    required Size area,
    required double deckCenterY,
  }) {
    final others = GameRules.opponentEntriesClockwiseFrom(myId, playerIds);
    if (others.isEmpty) return const SizedBox.shrink();

    final layout = OpponentArcLayout.compute(
      area,
      others.length,
      deckCenterY: deckCenterY,
    );
    final centers = layout.panelCenters();

    return Stack(
      clipBehavior: Clip.none,
      children: List.generate(others.length, (i) {
        final entry = others[i];
        final playerId = entry.value;
        final handCount = handCounts[playerId] ?? 0;
        final isHisTurn =
            playerIds.isNotEmpty && (currentTurnIndex % playerIds.length == entry.key);
        final isBurstWarning = handCount >= 6;
        final hasOpenJoker = openJokerPlayerIds.contains(playerId);
        final center = centers[i];

        return Positioned(
          left: center.dx - layout.panelWidth / 2,
          top: center.dy - layout.panelHeight / 2,
          width: layout.panelWidth,
          child: _buildOpponentPanel(
            key: opponentKeys[playerId],
            playerId: playerId,
            handCount: handCount,
            isHisTurn: isHisTurn,
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
    required bool isHisTurn,
    required bool isBurstWarning,
    required bool hasOpenJoker,
    required OpponentArcLayout layout,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black26,
        border: isHisTurn
            ? Border.all(color: Colors.yellow, width: 2)
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
          if (gameStarted && morrieRate > 0 && BotLogic.isBot(playerId))
            Text(
              '${MorrieRules.botFixedBalance}モリー',
              style: TextStyle(
                color: Colors.lightGreenAccent,
                fontSize: layout.pointsFontSize - 1,
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
        clipBehavior: Clip.none,
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

  Widget _buildMyHandSection(bool isMyTurn, {required bool inDrawCompetition}) {
    bool isBurstWarning = myHand.length >= 6;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(color: Colors.black26),
      child: Column(children: [
        if (isMyTurn || inDrawCompetition)
          Text(
            '${isMyTurn ? '（あなたのターン）' : ''}${inDrawCompetition ? ' · ドロー競合中' : ''}',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        if (gameStarted)
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 5),
            child: Text(
              '累計 ${playerPoints[myId] ?? 0}点',
              style: TextStyle(
                color: (playerPoints[myId] ?? 0) >= 0 ? Colors.amberAccent : Colors.redAccent,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          )
        else
          const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, constraints) {
            final layout = HandCardLayout.compute(constraints.maxWidth, myHand.length);
            return SizedBox(
              height: layout.height + 8,
              width: double.infinity,
              child: Center(
                child: _buildOverlappingHandRow(
                  cards: myHand,
                  layout: layout,
                  onTap: onCardTap,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 4),
        Text(
          '${myHand.length}枚',
          style: TextStyle(
            color: isBurstWarning ? Colors.red : Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ]),
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

  String _subtitle() {
    if (isSpectator) return '観戦を終了する場合はロビーへ戻ってください';
    if (seriesAutoContinuing) return 'まもなく次の対戦を開始します';
    if (awaitingGuestStayResponses) {
      if (isHost) return '参加者の回答: $guestStayReadyCount / $guestStayTotalCount 人';
      if (mustRespondToStay) return 'ルームに残りますか？';
      if (myStayResponseSubmitted) return '回答済み。他のプレイヤーを待っています…';
      return 'ホストの選択を待っています…';
    }
    if (isHost) return 'もう一度遊ぶ / ロビーへ';
    return 'ホストの選択を待っています…';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final cardWidth = (size.width * 0.9).clamp(280.0, 420.0);
    final maxCardHeight = size.height * 0.72;
    final titleSize = (size.width / 24).clamp(16.0, 20.0);
    final bodySize = (size.width / 28).clamp(12.0, 15.0);
    final headerSize = (size.width / 32).clamp(11.0, 13.0);

    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          width: cardWidth,
          constraints: BoxConstraints(maxHeight: maxCardHeight),
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1B3A1B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orangeAccent, width: 2),
          ),
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
              if (summary?.resultMessage != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.redAccent, width: 1.5),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: headerSize + 4),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'バースト',
                              style: TextStyle(
                                color: Colors.redAccent,
                                fontSize: bodySize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              summary!.resultMessage!,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: bodySize,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: _buildResultsTable(bodySize, headerSize),
                ),
              ),
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
              if (isHost && !awaitingGuestStayResponses && !seriesAutoContinuing && countdownSeconds != null) ...[
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
                  'シリーズ対戦中は自動的に次の対戦へ進みます',
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
                ] else
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: onLeaveToLobby,
                      child: const Text('ロビーへ'),
                    ),
                  ),
              ] else if (isHost) ...[
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: onHostRematch,
                    child: const Text('もう一度遊ぶ'),
                  ),
                ),
                const SizedBox(height: 8),
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
    );
  }

  Widget _buildResultsTable(double bodySize, double headerSize) {
    final players = summary?.players ?? [];
    final showRating = summary?.showRating ?? false;
    final showMorrie = summary?.showMorrie ?? false;

    if (players.isEmpty) {
      return Text(
        '結果を読み込み中…',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white54, fontSize: bodySize),
      );
    }

    return Table(
      columnWidths: const {
        0: IntrinsicColumnWidth(),
        1: FlexColumnWidth(),
        2: IntrinsicColumnWidth(),
        3: IntrinsicColumnWidth(),
        4: IntrinsicColumnWidth(),
        5: IntrinsicColumnWidth(),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white24)),
          ),
          children: [
            _headerCell('順位', headerSize),
            _headerCell('名前', headerSize),
            _headerCell('今回', headerSize),
            _headerCell('累計', headerSize),
            _headerCell(showMorrie ? 'モリー' : '', headerSize),
            _headerCell(showRating ? 'レート' : '', headerSize),
          ],
        ),
        for (final row in players)
          TableRow(
            children: [
              _bodyCell('${row.rank}', bodySize, align: TextAlign.center),
              _bodyCell(row.name, bodySize),
              _bodyCell(_formatDelta(row.matchDelta), bodySize, align: TextAlign.center),
              _bodyCell('${row.totalPoints}', bodySize, align: TextAlign.center),
              _bodyCell(
                showMorrie && row.morrieDelta != null
                    ? '${_formatDelta(row.morrieDelta)}'
                        '${row.morrieBalance != null ? ' → ${row.morrieBalance}' : ''}'
                    : '—',
                bodySize,
                align: TextAlign.end,
              ),
              _bodyCell(
                showRating && row.rating != null
                    ? '${row.rating} (${_formatDelta(row.ratingDelta)})'
                    : '—',
                bodySize,
                align: TextAlign.end,
              ),
            ],
          ),
      ],
    );
  }

  Widget _headerCell(String text, double size) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        style: TextStyle(color: Colors.white70, fontSize: size, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _bodyCell(String text, double size, {TextAlign align = TextAlign.start}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(color: Colors.white, fontSize: size),
      ),
    );
  }
}