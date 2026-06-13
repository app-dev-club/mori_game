import 'package:flutter/material.dart';
import '../../logic/game_rules.dart';
import '../../logic/room_config.dart';
import 'play_arrow_overlay.dart';

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
  final int playerCount;
  final int maxPlayers;
  final bool gameStarted;
  final String? statusMessage;
  final int? autoPlayCountdownSeconds;
  final bool postGameVisible;
  final String postGameMessage;
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
  final VoidCallback onMori, onDraw, onFlip;
  final Function(int) onCardTap;

  const GameBoardView({
    super.key, required this.roomId, required this.fieldNumber, required this.fieldSuit,
    required this.myHand, required this.playerIds, required this.playerNames, required this.myId, required this.handCounts,
    required this.currentTurnIndex, required this.isHost, this.hostId, this.lastPlayerId, this.lastDrawerId,
    required this.isDrawCompetitive,
    required this.isInitialPhase, required this.moriPhase, required this.hasDeclaredMori,
    required this.playerCount,
    required this.maxPlayers, required this.gameStarted,
    this.statusMessage,
    this.autoPlayCountdownSeconds,
    required this.postGameVisible,
    required this.postGameMessage,
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
      body: Stack(
        children: [
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
          _buildOthersStatus(opponentKeys),
          const Spacer(),
          _buildFieldArea(
            isMyTurn: isMyTurn,
            canDraw: canDraw,
            inDrawCompetition: inDrawCompetition,
            fieldKey: fieldKey,
            deckKey: deckKey,
          ),
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
              message: postGameMessage,
              isHost: isHost,
              countdownSeconds: postGameCountdownSeconds,
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
    required GlobalKey fieldKey,
    required GlobalKey deckKey,
  }) {
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

  Widget _buildOthersStatus(Map<String, GlobalKey> opponentKeys) {
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
          final isBurstWarning = handCount >= 6;

          return Container(
            key: opponentKeys[e.value],
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 4),
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
                  _playerLabel(e.value),
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                OpponentHandVisual(count: handCount, isBurstWarning: isBurstWarning),
              ],
            ),
          );
        }).toList(),
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

  Widget _buildMyHandSection(bool isMyTurn, {required bool inDrawCompetition}) {
    bool isBurstWarning = myHand.length >= 6;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: const BoxDecoration(color: Colors.black26),
      child: Column(children: [
        Text(
          "手札: ${myHand.length} / 7 ${isMyTurn ? '（あなたのターン）' : ''}${inDrawCompetition ? ' · ドロー競合中' : ''}",
          style: TextStyle(color: isBurstWarning ? Colors.red : Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        SizedBox(height: 100, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: myHand.length, itemBuilder: (c, i) => Padding(padding: const EdgeInsets.all(4), child: CardWidget(number: myHand[i].number, suit: myHand[i].suit, onTap: () => onCardTap(i))))),
      ]),
    );
  }
}

/// ゲーム終了後の再戦・退室UI
class PostGameOverlay extends StatelessWidget {
  final String message;
  final bool isHost;
  final int? countdownSeconds;
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
    required this.message,
    required this.isHost,
    this.countdownSeconds,
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

  String _subtitle() {
    if (awaitingGuestStayResponses) {
      if (isHost) {
        return '参加者の回答: $guestStayReadyCount / $guestStayTotalCount 人が残ると回答';
      }
      if (mustRespondToStay) {
        return 'ルームに残りますか？';
      }
      if (myStayResponseSubmitted) {
        return '回答を送信しました。他のプレイヤーを待っています…';
      }
      return 'ホストの選択を待っています…';
    }
    if (isHost) {
      return '「もう一度遊ぶ」を選ぶと参加者に残存確認を行います。全員の回答後にルームが公開されます。';
    }
    return 'ホストの選択を待っています…';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Container(
          width: 320,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF1B3A1B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orangeAccent, width: 2),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                _subtitle(),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              if (isHost && !awaitingGuestStayResponses && countdownSeconds != null) ...[
                const SizedBox(height: 12),
                Text(
                  '残り $countdownSeconds 秒（未選択でルーム閉鎖）',
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                ),
              ],
              if (awaitingGuestStayResponses && guestCountdownSeconds != null) ...[
                const SizedBox(height: 12),
                Text(
                  '残り $guestCountdownSeconds 秒（未回答は自動退室）',
                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold),
                ),
              ],
              const SizedBox(height: 20),
              if (awaitingGuestStayResponses) ...[
                if (isHost)
                  const Text(
                    '全員の回答が揃うとルームを公開します',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 12),
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
}