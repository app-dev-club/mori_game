import 'package:flutter/material.dart';
import 'package:mori_game/models/CardModel.dart';
import 'package:mori_game/widgets/CardWidget.dart';

class PlayerHandView extends StatelessWidget {
  final List<CardModel> myHand;
  final bool canMori;
  final Function(CardModel) onPlay;
  final VoidCallback onMori;

  const PlayerHandView({
    super.key,
    required this.myHand,
    required this.canMori,
    required this.onPlay,
    required this.onMori,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          ElevatedButton(
            onPressed: canMori ? onMori : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              disabledBackgroundColor: Colors.grey.withAlpha(50),
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
            ),
            child: const Text('もり！', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 20),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: myHand.map((c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: CardWidget(card: c, onTap: () => onPlay(c)),
              )).toList(),
            ),
          ),
          const SizedBox(height: 5),
          Text('手札: ${myHand.length}/7', style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}