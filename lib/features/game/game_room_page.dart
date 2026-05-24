import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../../services/firebase_db.dart';
import '../../logic/game_rules.dart';
import 'game_board_view.dart';

class GameRoomPage extends StatefulWidget {
  final String roomId;
  final bool isPrivate;
  const GameRoomPage({super.key, required this.roomId, this.isPrivate = false});

  @override
  State<GameRoomPage> createState() => _GameRoomPageState();
}

class _GameRoomPageState extends State<GameRoomPage> {
  late final FirebaseDB _db;
  StreamSubscription? _sub;
  String myId = DateTime.now().millisecondsSinceEpoch.toString();

  // 内部状態
  List<CardWidget> myHand = [];
  List<int> selectedIndices = [];
  String? hostId;
  List<String> playerIds = [];
  Map<String, int> handCounts = {};
  int fieldNumber = -1;
  Suit fieldSuit = Suit.joker;
  int currentTurn = 0;
  bool isInitialPhase = true;
  String? lastPlayerId;
  List<CardWidget> deck = [];

  @override
  void initState() {
    super.initState();
    _db = FirebaseDB(widget.roomId);
    _init();
  }

  Future<void> _init() async {
    final snap = await _db.getSnapshot();
    if (!snap.exists) {
      // ホスト：山札作成と初期化
      List<CardWidget> fullDeck = _generateDeck()..shuffle();
      final hand = fullDeck.sublist(0, 5);
      fullDeck.removeRange(0, 5);
      await _db.setupRoom(myId, fullDeck, widget.isPrivate);
      setState(() => myHand = hand);
    } else {
      // ゲスト：参加処理
      List<String> p = snap.child('players').exists 
          ? List<String>.from(snap.child('players').value as List) : [];
      if (!p.contains(myId)) p.add(myId);
      await _db.updateGameStatus({'players': p, 'playerHands/$myId': 5});
      // 山札から5枚取る（実際はDBから引くべきだが簡易化のため生成）
      setState(() => myHand = _generateDeck().take(5).toList());
    }
    _sub = _db.roomStream.listen(_onData);
  }

  void _onData(DatabaseEvent event) {
    final data = event.snapshot.value as Map?;
    if (data == null || !mounted) return;
    setState(() {
      hostId = data['host'];
      playerIds = List<String>.from(data['players'] ?? []);
      currentTurn = data['currentTurnIndex'] ?? 0;
      lastPlayerId = data['lastPlayerId'];
      if (data['playerHands'] != null) handCounts = Map<String, int>.from(data['playerHands']);
      if (data['field'] != null) {
        fieldNumber = data['field']['number'];
        fieldSuit = Suit.values.firstWhere((e) => e.name == data['field']['suit'], orElse: () => Suit.joker);
      }
      if (data['deck'] != null) {
        deck = (data['deck'] as List).map((i) => CardWidget(
          number: i['number'], 
          suit: Suit.values.firstWhere((e) => e.name == i['suit'])
        )).toList();
      }
      isInitialPhase = data['isInitialPhase'] ?? true;

      // 勝利判定
      if (data['winnerId'] != null) {
        _showGameOver(data['winnerId'] == myId ? "勝利！" : "敗北...");
      }
    });
  }

  // カードタップ時の挙動（ここがゲームの核）
  void _onCardTap(int index) {
    final card = myHand[index];
    int myIdx = playerIds.indexOf(myId);
    bool isMyTurn = (currentTurn % playerIds.length == myIdx);
    
    // 自分のターン、またはターン外でも同じ数字なら即座に出す
    if (isMyTurn || card.number == fieldNumber) {
      if (GameRules.canPlayNormal(fieldNumber, fieldSuit, card) || card.number == fieldNumber) {
        _executePlay([card]);
        return;
      }
    }

    // それ以外は「もり」のための複数選択
    setState(() {
      if (selectedIndices.contains(index)) {
        selectedIndices.remove(index);
      } else {
        selectedIndices.add(index);
      }
    });
  }

  // もり実行
  void _onMori() {
    final selectedCards = selectedIndices.map((i) => myHand[i]).toList();
    if (GameRules.isValidMori(fieldNumber, selectedCards)) {
      // 自滅チェック：直前に出したのが自分なら「もり」できない
      if (lastPlayerId == myId) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自滅はできません！')));
        return;
      }
      _db.updateGameStatus({'winnerId': myId});
    }
  }

  // ドロー処理
  void _onDraw() {
    if (deck.isEmpty) return;
    
    // バースト判定（手札7枚で負け）
    if (GameRules.isBurst(myHand.length + 1)) {
      _db.updateGameStatus({'winnerId': 'other_players'}); // 自分以外が勝利扱い
      return;
    }

    final drawn = deck.last;
    setState(() {
      myHand.add(drawn);
      selectedIndices.clear();
    });

    _db.updateGameStatus({
      'deck': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'playerHands/$myId': myHand.length,
      'currentTurnIndex': (currentTurn + 1) % playerIds.length,
    });
  }

  // プレイ実行（Firebase更新）
  void _executePlay(List<CardWidget> cards) {
    final lastCard = cards.last;
    setState(() {
      // 手札から削除
      for (var c in cards) {
        myHand.removeWhere((h) => h.number == c.number && h.suit == c.suit);
      }
      selectedIndices.clear();
    });

    _db.updateGameStatus({
      'field': {'number': lastCard.number, 'suit': lastCard.suit.name},
      'playerHands/$myId': myHand.length,
      'lastPlayerId': myId,
      'currentTurnIndex': (currentTurn + 1) % playerIds.length,
      'isInitialPhase': false, // 誰かが出した瞬間に初期フェーズ終了
    });

    if (myHand.isEmpty) {
      _db.updateGameStatus({'winnerId': myId});
    }
  }

  // ホストによる山札めくり（初期フェーズ）
  void _onFlip() {
    if (deck.isEmpty) return;
    final f = deck.last;
    _db.updateGameStatus({
      'field': {'number': f.number, 'suit': f.suit.name},
      'deck': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
    });
  }

  List<CardWidget> _generateDeck() {
    return [
      for (var s in Suit.values) 
        if (s != Suit.joker) 
          for (var i = 1; i <= 13; i++) CardWidget(number: i, suit: s),
      const CardWidget(number: 0, suit: Suit.joker)
    ];
  }

  void _showGameOver(String msg) {
    showDialog(
      context: context, 
      barrierDismissible: false, 
      builder: (_) => AlertDialog(
        title: Text(msg), 
        actions: [
          TextButton(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), 
            child: const Text("ロビーへ")
          )
        ]
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameBoardView(
      roomId: widget.roomId, 
      fieldNumber: fieldNumber, 
      fieldSuit: fieldSuit,
      myHand: myHand, 
      selectedIndices: selectedIndices, 
      playerIds: playerIds,
      myId: myId, 
      handCounts: handCounts, 
      currentTurnIndex: currentTurn,
      isHost: myId == hostId, 
      lastPlayerId: lastPlayerId, 
      isInitialPhase: isInitialPhase,
      onCardTap: _onCardTap, 
      onMori: _onMori, 
      onDraw: _onDraw, 
      onFlip: _onFlip,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}