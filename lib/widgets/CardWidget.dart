import 'package:flutter/material.dart';
import 'package:mori_game/models/CardModel.dart';

class CardWidget extends StatelessWidget {
  final CardModel card;
  final bool isSelected;
  final VoidCallback onTap;

  const CardWidget({
    super.key,
    required this.card,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // マークに応じた色
    Color color = (card.suit == Suit.heart || card.suit == Suit.diamond) 
                  ? Colors.red : Colors.black;
    if (card.suit == Suit.joker) color = Colors.purple;

    // 表示用テキスト (JQK変換)
    String label = _getLabel(card.number);
    String icon = _getIcon(card.suit);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        height: 90,
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.yellow[100] : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? Colors.orange : Colors.grey, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 2, offset: Offset(1, 1))],
        ),
        child: Center(
          child: Text(
            card.suit == Suit.joker ? 'JKR' : '$icon\n$label',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
        ),
      ),
    );
  }

  String _getLabel(int n) {
    if (n == 1) return 'A';
    if (n == 11) return 'J';
    if (n == 12) return 'Q';
    if (n == 13) return 'K';
    return n.toString();
  }

  String _getIcon(Suit s) {
    switch (s) {
      case Suit.spade: return '♠';
      case Suit.heart: return '♥';
      case Suit.diamond: return '♦';
      case Suit.club: return '♣';
      default: return '';
    }
  }
}