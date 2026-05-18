import 'package:flutter/material.dart';
import 'package:mori_game/models/CardModel.dart';
import 'package:mori_game/logic/MoriLogic.dart';
import 'package:mori_game/widgets/CardWidget.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  List<CardModel> deck = [];   
  List<CardModel> myHand = []; 
  
  int fieldNumber = 8;
  Suit fieldSuit = Suit.spade;

  @override
  void initState() {
    super.initState();
    _startNewGame();
  }

  void _startNewGame() {
    List<CardModel> newDeck = [];
    for (var suit in Suit.values) {
      if (suit == Suit.joker) {
        newDeck.add(CardModel(suit: suit, number: 0));
      } else {
        for (int i = 1; i <= 13; i++) {
          newDeck.add(CardModel(suit: suit, number: i));
        }
      }
    }
    newDeck.shuffle();

    setState(() {
      deck = newDeck;
      myHand = deck.sublist(0, 5);
      deck.removeRange(0, 5);
      
      final firstCard = deck.removeLast();
      fieldNumber = firstCard.number;
      fieldSuit = firstCard.suit;
    });
  }

  void _drawCard() {
    if (deck.isEmpty) return;
    setState(() {
      myHand.add(deck.removeLast());
      if (myHand.length > 7) {
        _showResultDialog("ゲームオーバー", "手札が8枚以上になったため負けです。");
      }
    });
  }

  // カードを出すメインロジック（修正版）
  void _playCard(CardModel card) {
    bool canPlay = false;

    if (fieldSuit == Suit.joker) {
      // 1. 場がジョーカーなら何でも出せる
      canPlay = true;
    } else if (card.number == fieldNumber) {
      // 2. 同じ数字なら出せる（割り込み・優先ルール）
      canPlay = true;
    } else if (card.suit == fieldSuit) {
      // 3. 同じマーク（スート）なら出せる（通常ルール）
      canPlay = true;
    }

    if (canPlay) {
      setState(() {
        fieldNumber = card.number;
        fieldSuit = card.suit;
        myHand.remove(card);
      });
      
      if (myHand.isEmpty) {
        _showResultDialog("勝利！", "手札をすべて出し切りました！");
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('同じ数字か同じマークしか出せません！'),
          duration: Duration(milliseconds: 500),
        ),
      );
    }
  }

  void _showResultDialog(String title, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _startNewGame();
            },
            child: const Text('もう一度遊ぶ'),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // もり判定（ジョーカーが場にある時は成立しないルールを適用）
    bool canMori = false;
    if (fieldSuit != Suit.joker) {
      canMori = MoriLogic.checkNormalMori(fieldNumber, myHand) ||
                MoriLogic.checkSpecialMori(fieldNumber, myHand);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text('もり - 練習モード'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 山札
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _drawCard,
                  child: Container(
                    width: 70, height: 100,
                    decoration: BoxDecoration(
                      color: Colors.blueGrey[800],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Center(
                      child: Text('山札', style: TextStyle(color: Colors.white))),
                  ),
                ),
                Text('残り: ${deck.length}枚', style: const TextStyle(color: Colors.white)),
              ],
            ),
          ),

          // 場札
          Column(
            children: [
              const Text('場のカード', style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 10),
              CardWidget(
                card: CardModel(suit: fieldSuit, number: fieldNumber),
                onTap: () {},
              ),
            ],
          ),

          // 手札とボタン
          Container(
            padding: const EdgeInsets.only(bottom: 30),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: canMori ? () => _showResultDialog("もり成功！", "おめでとうございます！") : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    disabledBackgroundColor: Colors.white10,
                    padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                  child: const Text('もり！', style: TextStyle(fontSize: 24)),
                ),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: myHand.map((card) => CardWidget(
                      card: card,
                      onTap: () => _playCard(card),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}