import 'package:flutter/material.dart';

class TurnInfoView extends StatelessWidget {
  final bool isInitialPhase;
  final bool isMyTurn;
  final bool iAmDrawer;

  const TurnInfoView({
    super.key,
    required this.isInitialPhase,
    required this.isMyTurn,
    required this.iAmDrawer,
  });

  @override
  Widget build(BuildContext context) {
    String text = isInitialPhase ? "【初期】数字を合わせて開始！" : (isMyTurn || iAmDrawer ? "あなたの番 / 競争中" : "相手の番です");
    Color color = (isMyTurn || iAmDrawer) ? Colors.orange : Colors.white70;

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }
}