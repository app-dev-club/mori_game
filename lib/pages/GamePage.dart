import 'package:flutter/material.dart';
import 'package:mori_game/models/CardModel.dart'; // package:プロジェクト名/... に書き換え
import 'package:mori_game/logic/MoriLogic.dart';
import 'package:mori_game/widgets/CardWidget.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  // 場の情報 (初期値)
  int fieldNumber = 8;
  Suit fieldSuit = Suit.spade;

  // 自分の手札 (テスト用データ)
  List<CardModel> myHand = [
    CardModel(suit: Suit.heart, number: 11), // J
    CardModel(suit: Suit.club, number: 3),
    CardModel(suit: Suit.diamond, number: 5),
  ];

  @override
  Widget build(BuildContext context) {
    // もり判定
    bool canMori = MoriLogic.checkNormalMori(fieldNumber, myHand) ||
                   MoriLogic.checkSpecialMori(fieldNumber, myHand);

    return Scaffold(
      backgroundColor: Colors.green[800], // テーブル風
      appBar: AppBar(title: const Text('もり - 練習モード')),
      body: Column(
        children: [
          const SizedBox(height: 40),
          const Text('場のカード', style: TextStyle(color: Colors.white)),
          // 場の表示
          CardWidget(
            card: CardModel(suit: fieldSuit, number: fieldNumber),
            onTap: () {}, // 場はタップ不可
          ),
          const Spacer(),
          // 手札の表示
          const Text('自分の手札', style: TextStyle(color: Colors.white)),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              alignment: WrapAlignment.center,
              children: myHand.map((card) => CardWidget(
                card: card,
                onTap: () {
                  // ここにカードを出すロジック（後ほど実装）
                },
              )).toList(),
            ),
          ),
          const SizedBox(height: 20),
          // もりボタン
          ElevatedButton(
            onPressed: canMori ? _showVictoryDialog : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: canMori ? Colors.orange : Colors.grey,
              minimumSize: const Size(200, 60),
            ),
            child: Text(canMori ? 'もり！可能' : 'まだ「もり」不可'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  void _showVictoryDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('成功！'),
        content: const Text('「もり」が成立しました！'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))
        ],
      ),
    );
  }
}