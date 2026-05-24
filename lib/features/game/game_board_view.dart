import 'package:flutter/material.dart';
import '../../logic/game_rules.dart';

enum Suit { spade, heart, diamond, club, joker }

class CardWidget extends StatelessWidget {
  final int number;
  final Suit suit;
  final bool isSelected;
  final VoidCallback? onTap;
  const CardWidget({super.key, required this.number, required this.suit, this.isSelected = false, this.onTap});

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
            Text(suit == Suit.joker ? 'J' : '$number', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black)),
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
  final List<int> selectedIndices;
  final List<String> playerIds;
  final String myId;
  final Map<String, int> handCounts;
  final int currentTurnIndex;
  final bool isHost;
  final String? lastPlayerId;
  final bool isInitialPhase;

  final Function(int) onCardTap;
  final VoidCallback onMori;
  final VoidCallback onDraw;
  final VoidCallback onFlip;

  const GameBoardView({
    super.key, required this.roomId, required this.fieldNumber, required this.fieldSuit,
    required this.myHand, required this.selectedIndices, required this.playerIds,
    required this.myId, required this.handCounts, required this.currentTurnIndex,
    required this.isHost, this.lastPlayerId, required this.isInitialPhase,
    required this.onCardTap, required this.onMori,
    required this.onDraw, required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    List<CardWidget> selectedCards = selectedIndices.map((i) => myHand[i]).toList();
    // もりの条件: 自分以外のカードに対して計算が合うこと
    bool canMori = GameRules.isValidMori(fieldNumber, selectedCards) && lastPlayerId != myId;

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(title: Text('ルーム: $roomId'), backgroundColor: Colors.transparent, elevation: 0),
      body: Column(
        children: [
          _buildOthersStatus(),
          const Spacer(),
          _buildFieldArea(),
          const Spacer(),
          if (canMori) 
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: ElevatedButton(
                onPressed: onMori,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15)),
                child: const Text("もり！", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ),
            ),
          _buildMyHandSection(),
        ],
      ),
    );
  }

  Widget _buildFieldArea() {
    return Column(children: [
      if (isInitialPhase && isHost)
        Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: ElevatedButton(
            onPressed: onFlip,
            style: ElevatedButton.styleFrom(backgroundColor: Colors.yellow[800], foregroundColor: Colors.white),
            child: const Text("山札をめくる", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        GestureDetector(
          onTap: onDraw,
          child: Container(width: 60, height: 90, decoration: BoxDecoration(color: Colors.blueGrey[800], borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.help_outline, color: Colors.white24)),
        ),
        const SizedBox(width: 20),
        fieldNumber == -1 ? Container(width: 60, height: 90, decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8))) : CardWidget(suit: fieldSuit, number: fieldNumber),
      ]),
    ]);
  }

  Widget _buildOthersStatus() => Row(mainAxisAlignment: MainAxisAlignment.center, children: playerIds.asMap().entries.where((e) => e.value != myId).map((e) => Column(children: [const Icon(Icons.person, color: Colors.white), Text('${handCounts[e.value] ?? 0}枚', style: const TextStyle(color: Colors.white))])).toList());
  Widget _buildMyHandSection() => Container(padding: const EdgeInsets.all(10), color: Colors.black26, child: Column(children: [Text("手札: ${myHand.length} / 7", style: TextStyle(color: myHand.length >= 6 ? Colors.red : Colors.white)), SizedBox(height: 100, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: myHand.length, itemBuilder: (c, i) => Padding(padding: const EdgeInsets.all(4), child: CardWidget(number: myHand[i].number, suit: myHand[i].suit, isSelected: selectedIndices.contains(i), onTap: () => onCardTap(i)))))]));
}