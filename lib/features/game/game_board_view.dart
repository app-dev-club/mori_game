import 'package:flutter/material.dart';
import '../../logic/game_rules.dart';
import '../../logic/room_config.dart';

enum Suit { spade, heart, diamond, club, joker }

class CardWidget extends StatelessWidget {
  final int number;
  final Suit suit;
  final VoidCallback? onTap;

  const CardWidget({super.key, required this.number, required this.suit, this.onTap});

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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60, height: 90,
        decoration: BoxDecoration(
          color: Colors.white, 
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.black, width: 1),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2, offset: Offset(1, 1))]
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSuitIcon(),
            Text(
              displayNumber, 
              style: TextStyle(
                fontSize: suit == Suit.joker ? 12 : 20, 
                fontWeight: FontWeight.bold, 
                color: Colors.black
              )
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuitIcon() {
    if (suit == Suit.joker) return const Text('🤡', style: TextStyle(fontSize: 20));
    String mark = {Suit.spade: '♠', Suit.heart: '♥', Suit.diamond: '♦', Suit.club: '♣'}[suit]!;
    Color color = (suit == Suit.heart || suit == Suit.diamond) ? Colors.red : Colors.black;
    return Text(mark, style: TextStyle(fontSize: 20, color: color));
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

  const OpponentHandVisual({
    super.key,
    required this.count,
    this.isBurstWarning = false,
  });

  static const double _cardWidth = 22;
  static const double _cardHeight = 33;
  static const double _overlap = 9;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return SizedBox(width: _cardWidth, height: _cardHeight);
    }

    final totalWidth = _cardWidth + (count - 1) * _overlap;
    return SizedBox(
      width: totalWidth,
      height: _cardHeight + 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: List.generate(count, (i) {
          final card = CardBackWidget(width: _cardWidth, height: _cardHeight);
          return Positioned(
            left: i * _overlap,
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

class GameBoardView extends StatelessWidget {
  final String roomId, myId, moriPhase;
  final int fieldNumber, currentTurnIndex;
  final Suit fieldSuit;
  final List<CardWidget> myHand;
  final List<String> playerIds;
  final Map<String, String> playerNames;
  final Map<String, int> handCounts;
  final bool isHost, isInitialPhase, hasDeclaredMori;
  final String? hostId, lastPlayerId, lastDrawerId, lastMoriPlayerId;
  final bool isDrawCompetitive;
  final List<CardWidget> moriRevealedHand;
  final String? moriRevealedType;
  final int rematchReadyCount, playerCount;
  final int maxPlayers;
  final bool gameStarted;
  final VoidCallback onMori, onDraw, onFlip;
  final Function(int) onCardTap;

  const GameBoardView({
    super.key, required this.roomId, required this.fieldNumber, required this.fieldSuit,
    required this.myHand, required this.playerIds, required this.playerNames, required this.myId, required this.handCounts,
    required this.currentTurnIndex, required this.isHost, this.hostId, this.lastPlayerId, this.lastDrawerId,
    required this.isDrawCompetitive,
    required this.isInitialPhase, required this.moriPhase, required this.hasDeclaredMori,
    required this.rematchReadyCount, required this.playerCount,
    required this.maxPlayers, required this.gameStarted,
    this.lastMoriPlayerId, required this.moriRevealedHand, this.moriRevealedType,
    required this.onCardTap, required this.onMori, required this.onDraw, required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    bool canMori = GameRules.isValidMori(fieldNumber, myHand);
    if (moriPhase == 'none' && lastPlayerId == myId) canMori = false;
    bool isButtonEnabled = canMori && !hasDeclaredMori;

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
        (isMyTurn || canDrawInCompetition) && GameRules.canDraw(myHand.length, lastDrawerId, myId);
    final bool inDrawCompetition = GameRules.canPlayInDrawCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: playerIds,
      myId: myId,
    );

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: Text(gameStarted ? 'ルーム: $roomId' : 'ルーム: $roomId（待機中 $playerCount/$maxPlayers人）'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          if (!gameStarted)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.teal.shade900,
              child: Text(
                RoomConfig.isRoomFull(playerCount, maxPlayers)
                    ? '定員に達しました。ホストが山札をめくるとゲーム開始します'
                    : '参加者を待っています… $playerCount / $maxPlayers 人',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          if (rematchReadyCount > 0 && rematchReadyCount < playerCount)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.amber.shade800,
              child: Text(
                '再戦待機中… $rematchReadyCount / $playerCount 人が準備完了',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          _buildOthersStatus(),
          const Spacer(),
          _buildFieldArea(isMyTurn: isMyTurn, canDraw: canDraw, inDrawCompetition: inDrawCompetition),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: ElevatedButton(
              onPressed: isButtonEnabled ? onMori : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: moriPhase == 'mori_declared' ? Colors.red : Colors.orange,
                disabledBackgroundColor: Colors.grey[700],
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15)
              ),
              child: Text(
                moriPhase == 'mori_declared' ? "もり返し！！" : "もり！", 
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isButtonEnabled ? Colors.white : Colors.white38)
              ),
            ),
          ),
          if (moriPhase == 'mori_declared')
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text("🔥 もり返し受付中 (5秒) 🔥", style: TextStyle(color: Colors.redAccent, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          if (moriPhase != 'none' && moriRevealedHand.isNotEmpty && lastMoriPlayerId != null)
            _buildMoriRevealedHandSection(),
          _buildMyHandSection(isMyTurn, inDrawCompetition: inDrawCompetition),
        ],
      ),
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
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: moriRevealedHand.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: CardWidget(
                  number: moriRevealedHand[i].number,
                  suit: moriRevealedHand[i].suit,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _playerLabel(String? playerId) {
    if (playerId == null) return '';
    if (playerId == 'system') return '山札';
    if (playerId == myId) {
      final myName = playerNames[myId];
      if (myName != null && myName.isNotEmpty) return 'あなた（$myName）';
      return 'あなた';
    }
    final idx = playerIds.indexOf(playerId);
    if (idx < 0) return '不明';
    final name = playerNames[playerId];
    final displayName = (name != null && name.isNotEmpty) ? name : 'プレイヤー${idx + 1}';
    if (hostId != null && playerId == hostId) return '$displayName（ホスト）';
    return displayName;
  }

  Widget _buildFieldArea({
    required bool isMyTurn,
    required bool canDraw,
    required bool inDrawCompetition,
  }) {
    final bool hasFieldCard = fieldNumber != -1;
    final String? fieldOwnerLabel =
        hasFieldCard && lastPlayerId != null ? _playerLabel(lastPlayerId) : null;

    return Column(children: [
      if (isInitialPhase && isHost)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ElevatedButton(onPressed: onFlip, style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[900]), child: const Text("山札をめくる", style: TextStyle(color: Colors.white))),
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
      if (fieldOwnerLabel != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black38,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orangeAccent, width: 1),
            ),
            child: Text(
              '$fieldOwnerLabel の出したカード',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(
          onTap: (canDraw && !isInitialPhase && moriPhase == 'none') ? onDraw : null,
          child: Container(
            width: 60, height: 90, 
            decoration: BoxDecoration(color: canDraw ? Colors.blueGrey[800] : Colors.grey[900], borderRadius: BorderRadius.circular(8), border: Border.all(color: canDraw ? Colors.yellow : Colors.white24)),
            child: const Icon(Icons.help_outline, color: Colors.white24),
          ),
        ),
        const SizedBox(width: 20),
        fieldNumber == -1
            ? Container(width: 60, height: 90, decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)))
            : CardWidget(suit: fieldSuit, number: fieldNumber),
      ]),
    ]);
  }

  Widget _buildOthersStatus() {
    final others = playerIds.asMap().entries.where((e) => e.value != myId).toList();
    if (others.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: others.map((e) {
          final handCount = handCounts[e.value] ?? 0;
          final isHisTurn = playerIds.isNotEmpty && (currentTurnIndex % playerIds.length == e.key);
          final playedField = fieldNumber != -1 && lastPlayerId == e.value;
          final isBurstWarning = handCount >= 6;

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.black26,
              border: isHisTurn
                  ? Border.all(color: Colors.yellow, width: 2)
                  : playedField
                      ? Border.all(color: Colors.orangeAccent, width: 2)
                      : Border.all(color: Colors.white12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _playerLabel(e.value),
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                OpponentHandVisual(count: handCount, isBurstWarning: isBurstWarning),
                if (playedField)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('場に出した', style: TextStyle(color: Colors.orangeAccent, fontSize: 9)),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMyHandSection(bool isMyTurn, {required bool inDrawCompetition}) {
    bool isBurstWarning = myHand.length >= 6;
    final bool iPlayedField = fieldNumber != -1 && lastPlayerId == myId;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        border: iPlayedField ? const Border(top: BorderSide(color: Colors.orangeAccent, width: 2)) : null,
      ),
      child: Column(children: [
        Text(
          "手札: ${myHand.length} / 7 ${isMyTurn ? '（あなたのターン）' : ''}${inDrawCompetition ? ' · ドロー競合中' : ''}${iPlayedField ? ' · 場に出した' : ''}",
          style: TextStyle(color: isBurstWarning ? Colors.red : Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        SizedBox(height: 100, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: myHand.length, itemBuilder: (c, i) => Padding(padding: const EdgeInsets.all(4), child: CardWidget(number: myHand[i].number, suit: myHand[i].suit, onTap: () => onCardTap(i))))),
      ]),
    );
  }
}