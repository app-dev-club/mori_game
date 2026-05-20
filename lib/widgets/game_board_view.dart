import 'package:flutter/material.dart';
import 'package:mori_game/models/CardModel.dart';
import 'package:mori_game/widgets/CardWidget.dart';

class GameBoardView extends StatelessWidget {
  final bool isInitialPhase;
  final bool isHost;
  final bool isMyTurn;
  final int fieldNumber;
  final Suit fieldSuit;
  final VoidCallback onDraw;
  final VoidCallback onFlip;

  const GameBoardView({
    super.key,
    required this.isInitialPhase,
    required this.isHost,
    required this.isMyTurn,
    required this.fieldNumber,
    required this.fieldSuit,
    required this.onDraw,
    required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionButton(
              label: 'ドロー',
              onTap: isMyTurn && !isInitialPhase ? onDraw : null,
              isActive: isMyTurn && !isInitialPhase,
            ),
            if (isInitialPhase && isHost) ...[
              const SizedBox(width: 20),
              _ActionButton(
                label: 'めくる',
                onTap: onFlip,
                isActive: true,
                color: Colors.orange[800],
                icon: Icons.refresh,
              ),
            ],
          ],
        ),
        const SizedBox(height: 20),
        Text('場: ${fieldSuit.name} $fieldNumber', 
          style: const TextStyle(color: Colors.yellow, fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        CardWidget(card: CardModel(suit: fieldSuit, number: fieldNumber), onTap: () {}),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool isActive;
  final Color? color;
  final IconData? icon;

  const _ActionButton({required this.label, this.onTap, required this.isActive, this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70, height: 100,
        decoration: BoxDecoration(
          color: isActive ? (color ?? Colors.blueGrey[900]) : Colors.grey,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) Icon(icon, color: Colors.white, size: 20),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}