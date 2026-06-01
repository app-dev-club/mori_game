import 'package:flutter/material.dart';
import '../../logic/game_rules.dart';

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

class GameBoardView extends StatelessWidget {
  final String roomId, myId, moriPhase;
  final int fieldNumber, currentTurnIndex;
  final Suit fieldSuit;
  final List<CardWidget> myHand;
  final List<String> playerIds;
  final Map<String, int> handCounts;
  final bool isHost, isInitialPhase, hasDeclaredMori;
  final String? hostId, lastPlayerId, lastDrawerId, lastMoriPlayerId;
  final List<CardWidget> moriRevealedHand;
  final String? moriRevealedType;
  final int rematchReadyCount, playerCount;
  final VoidCallback onMori, onDraw, onFlip;
  final Function(int) onCardTap;

  const GameBoardView({
    super.key, required this.roomId, required this.fieldNumber, required this.fieldSuit,
    required this.myHand, required this.playerIds, required this.myId, required this.handCounts,
    required this.currentTurnIndex, required this.isHost, this.hostId, this.lastPlayerId, this.lastDrawerId,
    required this.isInitialPhase, required this.moriPhase, required this.hasDeclaredMori,
    required this.rematchReadyCount, required this.playerCount,
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
    bool canDraw = isMyTurn && GameRules.canDraw(myHand.length, lastDrawerId, myId);

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(title: Text('ルーム: $roomId'), backgroundColor: Colors.transparent, elevation: 0),
      body: Column(
        children: [
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
          _buildFieldArea(isMyTurn: isMyTurn, canDraw: canDraw),
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
          _buildMyHandSection(isMyTurn),
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
    if (playerId == myId) return 'あなた';
    final idx = playerIds.indexOf(playerId);
    if (idx < 0) return '不明';
    final n = idx + 1;
    if (hostId != null && playerId == hostId) return 'プレイヤー$n（ホスト）';
    return 'プレイヤー$n';
  }

  Widget _buildFieldArea({required bool isMyTurn, required bool canDraw}) {
    final bool hasFieldCard = fieldNumber != -1;
    final String? fieldOwnerLabel =
        hasFieldCard && lastPlayerId != null ? _playerLabel(lastPlayerId) : null;

    return Column(children: [
      if (isInitialPhase && isHost)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ElevatedButton(onPressed: onFlip, style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[900]), child: const Text("山札をめくる", style: TextStyle(color: Colors.white))),
        ),
      if (fieldSuit == Suit.joker && !isInitialPhase) const Text("🃏 ジョーカー！誰でも出せます！", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
      if (!isMyTurn && fieldSuit != Suit.joker && fieldNumber != -1 && moriPhase == 'none') const Text("同じ数字なら割り込み可能", style: TextStyle(color: Colors.white70, fontSize: 10)),
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center, 
      children: playerIds.asMap().entries.where((e) => e.value != myId).map((e) {
        bool isHisTurn = playerIds.isNotEmpty && (currentTurnIndex % playerIds.length == e.key);
        bool playedField = fieldNumber != -1 && lastPlayerId == e.value;
        return Container(
          padding: const EdgeInsets.all(8), margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            border: isHisTurn
                ? Border.all(color: Colors.yellow, width: 2)
                : playedField
                    ? Border.all(color: Colors.orangeAccent, width: 2)
                    : null,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            const Icon(Icons.person, color: Colors.white),
            Text(_playerLabel(e.value), style: const TextStyle(color: Colors.white70, fontSize: 10)),
            Text('${handCounts[e.value] ?? 0}枚', style: const TextStyle(color: Colors.white)),
            if (playedField) const Text('場に出した', style: TextStyle(color: Colors.orangeAccent, fontSize: 9)),
          ]),
        );
      }).toList()
    );
  }

  Widget _buildMyHandSection(bool isMyTurn) {
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
          "手札: ${myHand.length} / 7 ${isMyTurn ? '（あなたのターン）' : ''}${iPlayedField ? ' · 場に出した' : ''}",
          style: TextStyle(color: isBurstWarning ? Colors.red : Colors.white, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        SizedBox(height: 100, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: myHand.length, itemBuilder: (c, i) => Padding(padding: const EdgeInsets.all(4), child: CardWidget(number: myHand[i].number, suit: myHand[i].suit, onTap: () => onCardTap(i))))),
      ]),
    );
  }
}