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
  // 修正：DatabaseURLをここでも明示的に指定（パースエラー対策）
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
    _checkAndInitializeFirebase();
  }

  @override
  void dispose() {
    _roomSubscription?.cancel();
    super.dispose();
  }

  void _listenToRoom() {
    // 既存の監視を一旦キャンセルしてから再開
    _roomSubscription?.cancel();
    _roomSubscription = _roomRef.onValue.listen((event) {
      debugPrint("Firebaseからデータを受信しました: ${event.snapshot.value}");
      final data = event.snapshot.value as Map?;
      if (data == null) return;

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
        }
      }
    }, onError: (error) {
      debugPrint("Firebase監視エラー: $error");
    });
  }

  Future<void> _checkAndInitializeFirebase() async {
    try {
      final snapshot = await _roomRef.get();
      if (snapshot.exists && snapshot.child('field').value != null) {
        debugPrint("既存の部屋を発見しました");
        return;
      }

      debugPrint("新規部屋を初期化します");
      final firstCard = deck.removeLast();
      await _roomRef.set({
        'field': {
          'number': firstCard.number,
          'suit': firstCard.suit.name,
        },
        'isInitialPhase': true,
        'status': 'playing'
      });
    } catch (e) {
      debugPrint("初期化エラー: $e");
    }
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
      debugPrint("${card.number} を送信中...");
      // 先に手札から消して体感速度を上げる
      setState(() => myHand.remove(card));

      _roomRef.update({
        'field': {'number': card.number, 'suit': card.suit.name},
        'isInitialPhase': false, 
      }).then((_) {
        debugPrint("送信完了");
      }).catchError((e) {
        debugPrint("送信失敗: $e");
        // 失敗したら手札に戻す
        setState(() => myHand.add(card));
      });
    }
  }

  // --- UI部分は基本的に同じですが、読み込み中表示を追加 ---

  @override
  Widget build(BuildContext context) {
    if (fieldNumber == -1) {
      return const Scaffold(
        backgroundColor: Color(0xFF1B5E20),
        body: Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 10),
            Text("Firebase接続中...", style: TextStyle(color: Colors.white))
          ],
        )),
      );
    }

    // (buildの続きは既存のコードと同じ)
    return _buildGameUI(); // 下記にUI部分をまとめました
  }

  Widget _buildGameUI() {
    bool canMori = !isInitialPhase && fieldSuit != Suit.joker &&
                   (MoriLogic.checkNormalMori(fieldNumber, myHand) ||
                    MoriLogic.checkSpecialMori(fieldNumber, myHand));

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(title: const Text('もり - 同期デバッグ版'), backgroundColor: Colors.transparent),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 山札
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: GestureDetector(
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
          ),
          // 場
          Column(
            children: [
              Text(isInitialPhase ? '【初期】数字を合わせろ' : '場', style: const TextStyle(color: Colors.yellow)),
              const SizedBox(height: 10),
              CardWidget(card: CardModel(suit: fieldSuit, number: fieldNumber), onTap: () {}),
            ],
          ),
          // 手札
          Container(
            padding: const EdgeInsets.only(bottom: 30),
            child: Column(
              children: [
                ElevatedButton(
                  onPressed: canMori ? () => _showResultDialog("もり！", "成功") : null,
                  child: const Text('もり！'),
                ),
                const SizedBox(height: 20),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: myHand.map((card) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: CardWidget(card: card, onTap: () => _playCard(card)),
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

  // (drawCardやshowResultDialogなどは以前のものを流用)
  void _drawCard() {
    if (deck.isEmpty || isInitialPhase) return;
    if (myHand.length == 7) {
      if (_hasPlayableCard()) return;
      _showResultDialog("バースト", "敗北");
      return;
    }
    setState(() {
      myHand.add(deck.removeLast());
      if (myHand.length == 7 && !_hasPlayableCard()) _showResultDialog("バースト", "敗北");
    });
  }

  bool _hasPlayableCard() => fieldSuit == Suit.joker || myHand.any((c) => c.number == fieldNumber || c.suit == fieldSuit);

  void _showResultDialog(String title, String message) {
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(title), content: Text(message),
      actions: [TextButton(onPressed: () { 
        Navigator.pop(context); 
        _roomRef.remove().then((_) => _initializeGameSession());
      }, child: const Text('リセット'))],
    ));
  }

  void _initializeGameSession() {
    _prepareLocalCards();
    _checkAndInitializeFirebase();
  }
}