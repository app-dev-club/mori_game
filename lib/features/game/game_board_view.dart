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
  final String? lastPlayerId, lastDrawerId;
  final int rematchReadyCount, playerCount;
  final VoidCallback onMori, onDraw, onFlip;
  final Function(int) onCardTap;

  const GameBoardView({
    super.key, required this.roomId, required this.fieldNumber, required this.fieldSuit,
    required this.myHand, required this.playerIds, required this.myId, required this.handCounts,
    required this.currentTurnIndex, required this.isHost, this.lastPlayerId, this.lastDrawerId,
    required this.isInitialPhase, required this.moriPhase, required this.hasDeclaredMori,
    required this.rematchReadyCount, required this.playerCount,
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
          _buildMyHandSection(isMyTurn),
        ],
      ),
    );
  }

  Widget _buildFieldArea({required bool isMyTurn, required bool canDraw}) {
    return Column(children: [
      if (isInitialPhase && isHost)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ElevatedButton(onPressed: onFlip, style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[900]), child: const Text("山札をめくる", style: TextStyle(color: Colors.white))),
        ),
      if (fieldSuit == Suit.joker && !isInitialPhase) const Text("🃏 ジョーカー！誰でも出せます！", style: TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
      if (!isMyTurn && fieldSuit != Suit.joker && fieldNumber != -1 && moriPhase == 'none') const Text("同じ数字なら割り込み可能", style: TextStyle(color: Colors.white70, fontSize: 10)),
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
        fieldNumber == -1 ? Container(width: 60, height: 90, decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8))) : CardWidget(suit: fieldSuit, number: fieldNumber),
      ]),
    ]);
  }

  Widget _buildOthersStatus() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center, 
      children: playerIds.asMap().entries.where((e) => e.value != myId).map((e) {
        bool isHisTurn = playerIds.isNotEmpty && (currentTurnIndex % playerIds.length == e.key);
        return Container(
          padding: const EdgeInsets.all(8), margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(border: isHisTurn ? Border.all(color: Colors.yellow, width: 2) : null, borderRadius: BorderRadius.circular(8)),
          child: Column(children: [const Icon(Icons.person, color: Colors.white), Text('${handCounts[e.value] ?? 0}枚', style: const TextStyle(color: Colors.white))]),
        );
      }).toList()
    );
  }

  Widget _buildMyHandSection(bool isMyTurn) {
    bool isBurstWarning = myHand.length >= 6;
    return Container(
      padding: const EdgeInsets.all(10), color: Colors.black26,
      child: Column(children: [
        Text("手札: ${myHand.length} / 7 ${isMyTurn ? '（あなたのターン）' : ''}", style: TextStyle(color: isBurstWarning ? Colors.red : Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        SizedBox(height: 100, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: myHand.length, itemBuilder: (c, i) => Padding(padding: const EdgeInsets.all(4), child: CardWidget(number: myHand[i].number, suit: myHand[i].suit, onTap: () => onCardTap(i))))),
      ]),
    );
  }
}