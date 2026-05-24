import 'package:flutter/material.dart';
import '../../logic/game_rules.dart';

enum Suit { spade, heart, diamond, club, joker }

class CardWidget extends StatelessWidget {
  final int number;
  final Suit suit;
  final bool isSelected; // 複数選択用
  final VoidCallback? onTap;

  const CardWidget({
    super.key, required this.number, required this.suit, 
    this.isSelected = false, this.onTap
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60, height: 90,
        decoration: BoxDecoration(
          color: isSelected ? Colors.yellow[100] : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Colors.orange : Colors.black, width: isSelected ? 3 : 1),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildSuitIcon(),
            Text(suit == Suit.joker ? 'J' : '$number',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
          ],
        ),
      ),
    );
  }

  Widget _buildSuitIcon() {
    String mark = {Suit.spade: '♠', Suit.heart: '♥', Suit.diamond: '♦', Suit.club: '♣', Suit.joker: '🤡'}[suit]!;
    Color color = (suit == Suit.heart || suit == Suit.diamond) ? Colors.red : Colors.black;
    return Text(mark, style: TextStyle(fontSize: 20, color: color));
  }
}

class GameBoardView extends StatelessWidget {
  final String roomId;
  final int fieldNumber;
  final Suit fieldSuit;
  final List<CardWidget> myHand;
  final List<int> selectedIndices; // 選択中のインデックス
  final List<String> playerIds;
  final String myId;
  final Map<String, int> handCounts;
  final int currentTurnIndex;
  final bool isHost;
  final String? lastPlayerId;
  final bool isInitialPhase;

  final Function(int) onCardTap;
  final VoidCallback onPlay;
  final VoidCallback onMori;
  final VoidCallback onDraw;
  final VoidCallback onFlip;

  const GameBoardView({
    super.key, required this.roomId, required this.fieldNumber, required this.fieldSuit,
    required this.myHand, required this.selectedIndices, required this.playerIds,
    required this.myId, required this.handCounts, required this.currentTurnIndex,
    required this.isHost, this.lastPlayerId, required this.isInitialPhase,
    required this.onCardTap, required this.onPlay, required this.onMori,
    required this.onDraw, required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    int myIdx = playerIds.indexOf(myId);
    bool isMyTurn = (currentTurnIndex % playerIds.length == myIdx);
    
    List<CardWidget> selectedCards = selectedIndices.map((i) => myHand[i]).toList();
    bool canMori = GameRules.isValidMori(fieldNumber, selectedCards) && lastPlayerId != myId;

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(title: Text('ルーム: $roomId'), backgroundColor: Colors.transparent),
      body: Column(
        children: [
          _buildOthersStatus(),
          const Spacer(),
          _buildFieldArea(),
          const Spacer(),
          if (canMori) _buildBigButton("もり！", Colors.orange, onMori),
          if (isMyTurn && selectedIndices.length == 1) _buildBigButton("出す", Colors.blue, onPlay),
          _buildMyHandSection(),
        ],
      ),
    );
  }

  Widget _buildBigButton(String label, Color color, VoidCallback action) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ElevatedButton(
        onPressed: action,
        style: ElevatedButton.styleFrom(backgroundColor: color, padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15)),
        child: Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  Widget _buildFieldArea() {
    return Column(children: [
      if (isInitialPhase && isHost) ElevatedButton(onPressed: onFlip, child: const Text("山札をめくって開始")),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(
          onTap: onDraw,
          child: Container(width: 60, height: 90, decoration: BoxDecoration(color: Colors.blueGrey[700], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.help_outline, color: Colors.white24)),
        ),
        const SizedBox(width: 20),
        fieldNumber == -1 ? const SizedBox(width: 60, height: 90) : CardWidget(suit: fieldSuit, number: fieldNumber),
      ]),
      const Text("山札 / 場札", style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }

  Widget _buildMyHandSection() {
    bool isBurstWarning = myHand.length >= 6;
    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.black26,
      child: Column(
        children: [
          Text("手札: ${myHand.length} / 7", style: TextStyle(color: isBurstWarning ? Colors.red : Colors.white)),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: myHand.length,
              itemBuilder: (context, index) {
                final card = myHand[index];
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: CardWidget(
                    number: card.number, suit: card.suit,
                    isSelected: selectedIndices.contains(index),
                    onTap: () => onCardTap(index),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOthersStatus() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: playerIds.asMap().entries.map((e) {
        if (e.value == myId) return const SizedBox();
        bool isHisTurn = (currentTurnIndex % playerIds.length == e.key);
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: isHisTurn ? Border.all(color: Colors.yellow) : null),
          child: Column(children: [const Icon(Icons.person, color: Colors.white), Text('${handCounts[e.value] ?? 0}枚', style: const TextStyle(color: Colors.white))]),
        );
      }).toList(),
    );
  }
}