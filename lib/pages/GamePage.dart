import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:mori_game/models/CardModel.dart';
import 'package:mori_game/logic/MoriLogic.dart';
import 'package:mori_game/widgets/CardWidget.dart';
import 'dart:async';

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  // DatabaseURLを明示的に指定して接続を安定させる
  final DatabaseReference _roomRef = FirebaseDatabase.instance.ref('rooms/test_room');

  StreamSubscription<DatabaseEvent>? _roomSubscription;

  List<CardModel> deck = [];   
  List<CardModel> myHand = []; 
  
  int fieldNumber = -1; // -1: 読み込み中
  Suit fieldSuit = Suit.joker;
  bool isInitialPhase = true;

  @override
  void initState() {
    super.initState();
    _prepareLocalCards();
    _listenToRoom();
    
    // Firebaseの準備が整うまで少し待ってから初期化チェック
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _checkAndInitializeFirebase();
    });
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }

  void _listenToRoom() {
    _roomSubscription = _roomRef.onValue.listen((event) {
      final data = event.snapshot.value as Map?;
      if (data == null) {
        // 部屋が空の状態（リセット後など）
        setState(() => fieldNumber = -1);
        return;
      }

      final field = data['field'] as Map?;
      if (field != null) {
        if (mounted) {
          setState(() {
            fieldNumber = field['number'];
            fieldSuit = Suit.values.firstWhere(
              (e) => e.name == field['suit'],
              orElse: () => Suit.joker,
            );
            isInitialPhase = data['isInitialPhase'] ?? true;
          });

          // 【修正】データを受信した結果「誰も出せない初期状態」なら、
          // 0.5秒待ってから自分がめくる（全員で実行してもFirebaseが順序制御します）
          if (isInitialPhase && !_hasInitialMatchingCard()) {
            _drawNextInitialCard();
          }
        }
      }
    });
  }

  Future<void> _checkAndInitializeFirebase() async {
    final snapshot = await _roomRef.get();
    
    // 1. 部屋が全くない、またはfieldがない場合のみ初期化
    if (!snapshot.exists || snapshot.child('field').value == null) {
      print("部屋を新規作成します...");
      _forceDrawFromDeckToField();
    } else {
      // 2. 部屋はあるが「場に出せるカードが手札にない」場合
      // listen側でも動きますが、念のため起動時にもチェック
      if (isInitialPhase && !_hasInitialMatchingCard()) {
        _drawNextInitialCard();
      }
    }
  }

  // 初期フェーズ用：同じ数字があるか、または場がJOKERか
  bool _hasInitialMatchingCard() {
    // 読み込み中(-1)は判定しない
    if (fieldNumber == -1) return true; 
    // JOKERなら誰でも出せるので「持っている」とみなす
    if (fieldSuit == Suit.joker) return true;
    // 手札に同じ数字があればOK
    return myHand.any((c) => c.number == fieldNumber);
  }

  // 山札から次のカードをめくる
  void _drawNextInitialCard() {
    // すでに解決済みなら何もしない
    if (!isInitialPhase || _hasInitialMatchingCard()) return;

    // 複数の端末で同時にめくらないよう、少しディレイをかける
    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted && isInitialPhase && !_hasInitialMatchingCard()) {
        _forceDrawFromDeckToField();
      }
    });
  }

  // Firebaseの場を「山札の次のカード」で強制更新
  Future<void> _forceDrawFromDeckToField() async {
    if (deck.isEmpty) return;
    
    final nextCard = deck.removeLast();
    print("山札から場を更新: ${nextCard.number}");
    
    await _roomRef.update({
      'field': {
        'number': nextCard.number,
        'suit': nextCard.suit.name,
      },
      'isInitialPhase': true, // まだ初期フェーズのまま
    });
  }

  void _prepareLocalCards() {
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
      myHand = newDeck.sublist(0, 5);
      deck = newDeck..removeRange(0, 5);
    });
  }

  void _playCard(CardModel card) {
    bool canPlay = false;
    if (fieldSuit == Suit.joker || 
        (isInitialPhase && card.number == fieldNumber) ||
        (!isInitialPhase && (card.number == fieldNumber || card.suit == fieldSuit))) {
      canPlay = true;
    }

    if (canPlay) {
      setState(() => myHand.remove(card));
      _roomRef.update({
        'field': {'number': card.number, 'suit': card.suit.name},
        'isInitialPhase': false, 
      });
    }
  }

  void _drawCard() {
    if (deck.isEmpty || isInitialPhase) return;
    if (myHand.length == 7) {
      if (_hasPlayableCard()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('出せるカードがあります')));
        return;
      }
      _showResultDialog("バースト", "敗北です。");
      return;
    }
    setState(() {
      myHand.add(deck.removeLast());
      if (myHand.length == 7 && !_hasPlayableCard()) _showResultDialog("バースト", "敗北です。");
    });
  }

  bool _hasPlayableCard() => fieldSuit == Suit.joker || myHand.any((c) => c.number == fieldNumber || c.suit == fieldSuit);

  void _showResultDialog(String title, String message) {
    showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(
      title: Text(title), content: Text(message),
      actions: [TextButton(onPressed: () { 
        Navigator.pop(context); 
        _resetGame();
      }, child: const Text('リセット'))],
    ));
  }

  void _resetGame() {
    _roomRef.remove().then((_) {
      _prepareLocalCards();
      _checkAndInitializeFirebase();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (fieldNumber == -1) {
      return const Scaffold(backgroundColor: Color(0xFF1B5E20), body: Center(child: CircularProgressIndicator(color: Colors.white)));
    }

    bool canMori = !isInitialPhase && fieldSuit != Suit.joker &&
                   (MoriLogic.checkNormalMori(fieldNumber, myHand) ||
                    MoriLogic.checkSpecialMori(fieldNumber, myHand));

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(title: const Text('もり - 同期プレイ'), backgroundColor: Colors.transparent, elevation: 0),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              children: [
                GestureDetector(
                  onTap: _drawCard,
                  child: Container(
                    width: 70, height: 100,
                    decoration: BoxDecoration(
                      color: isInitialPhase ? Colors.grey : Colors.blueGrey[900],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Center(child: Text('ドロー', style: TextStyle(color: Colors.white))),
                  ),
                ),
                Text('山札: ${deck.length}', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          Column(
            children: [
              Text(isInitialPhase ? '【初期】数字を合わせろ' : '共有の場', style: const TextStyle(color: Colors.yellow, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              CardWidget(card: CardModel(suit: fieldSuit, number: fieldNumber), onTap: () {}),
            ],
          ),
          Container(
            padding: const EdgeInsets.only(bottom: 30),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: canMori ? () => _showResultDialog("もり！", "成功！") : null,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent),
                  child: const Text('もり！'),
                ),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: myHand.map((card) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: CardWidget(card: card, onTap: () => _playCard(card)),
                    )).toList(),
                  ),
                ),
                const SizedBox(height: 10),
                Text('手札: ${myHand.length}/7', style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}