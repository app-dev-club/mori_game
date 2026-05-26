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

// WidgetsBindingObserver を追加してアプリのバックグラウンド放置を監視
class _GameRoomPageState extends State<GameRoomPage> with WidgetsBindingObserver {
  late final FirebaseDB _db;
  StreamSubscription? _sub;
  String myId = DateTime.now().millisecondsSinceEpoch.toString();

  // 内部状態（State）
  List<CardWidget> myHand = [];
  String? hostId;
  List<String> playerIds = [];
  Map<String, int> handCounts = {};
  int fieldNumber = -1;
  Suit fieldSuit = Suit.joker;
  int currentTurn = 0;
  bool isInitialPhase = true;
  String? lastPlayerId;
  List<CardWidget> deck = [];

  // もりシステム用
  String moriPhase = 'none'; 
  String? lastMoriPlayerId;  
  String? loserPlayerId;     
  Timer? _moriTimer;         
  String _lastTrackedMoriPlayer = ''; 

  // 部屋の開閉状態管理フラグ
  String roomStatus = 'open'; // 'open', 'closed'
  bool _isClosedDialogShown = false;

  bool get isHost => myId == hostId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ライフサイクル監視の開始
    _db = FirebaseDB(widget.roomId);
    _init();
  }

  @override
  void dispose() {
    _cleanupRoomOnLeave(); // 退室時のクリーンアップ
    WidgetsBinding.instance.removeObserver(this); // ライフサイクル監視の解除
    _sub?.cancel();
    _moriTimer?.cancel();
    super.dispose();
  }

  // ホストがアプリをバックグラウンド（放置）にした時の検知
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isHost && (state == AppLifecycleState.paused || state == AppLifecycleState.detached)) {
      // ホストがアプリを閉じる、または別タブ放置などで完全にバックグラウンドに入ったら即座に部屋を閉鎖
      _closeRoomForcefully();
    }
  }

  Future<void> _init() async {
    final snap = await _db.getSnapshot();
    if (!snap.exists) {
      // ホスト：山札作成と初期化
      List<CardWidget> fullDeck = _generateDeck()..shuffle();
      final hand = fullDeck.sublist(0, 5);
      fullDeck.removeRange(0, 5);
      
      await _db.setupRoom(myId, fullDeck, widget.isPrivate);
      
      // 不意の通信切断（タブを閉じる、回線落ち）に備えて、Firebase側に削除/閉鎖予約を入れる
      final roomRef = FirebaseDatabase.instance.ref('rooms/${widget.roomId}');
      await roomRef.onDisconnect().update({'roomStatus': 'closed'});

      setState(() => myHand = hand);
    } else {
      // ゲスト：参加処理
      bool isStarted = snap.child('gameStarted').value == true;
      String currentStatus = snap.child('roomStatus').value as String? ?? 'open';
      
      if (isStarted || currentStatus == 'closed') {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _showErrorDialog("このゲームは既に開始されているか、閉鎖されているため入室できません。");
        });
        return;
      }

      List<String> p = snap.child('players').exists 
          ? List<String>.from(snap.child('players').value as List) : [];
      if (!p.contains(myId)) p.add(myId);

      List<dynamic> rawDeck = snap.child('deck').value as List<dynamic>? ?? [];
      List<CardWidget> currentDeck = rawDeck.map((i) => CardWidget(
        number: i['number'], suit: Suit.values.firstWhere((e) => e.name == i['suit'])
      )).toList();

      List<CardWidget> initialHand = [];
      for (int i = 0; i < 5; i++) {
        if (currentDeck.isNotEmpty) initialHand.add(currentDeck.removeLast());
      }

      await _db.updateGameStatus({
        'players': p,
        'playerHands/$myId': initialHand.length,
        'deck': currentDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      });
      setState(() => myHand = initialHand);
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
      roomStatus = data['roomStatus'] ?? 'open';

      if (data['playerHands'] != null) handCounts = Map<String, int>.from(data['playerHands']);
      
      if (data['field'] != null) {
        fieldNumber = data['field']['number'];
        fieldSuit = Suit.values.firstWhere((e) => e.name == data['field']['suit'], orElse: () => Suit.joker);
      }
      if (data['deck'] != null) {
        deck = (data['deck'] as List).map((i) => CardWidget(
          number: i['number'], suit: Suit.values.firstWhere((e) => e.name == i['suit'])
        )).toList();
      }
      isInitialPhase = data['isInitialPhase'] ?? true;

      moriPhase = data['moriPhase'] ?? 'none';
      lastMoriPlayerId = data['lastMoriPlayerId'];
      loserPlayerId = data['loserPlayerId'];

      // --- 部屋の閉鎖監視ロジック ---
      if (roomStatus == 'closed' && !isHost && !_isClosedDialogShown) {
        _isClosedDialogShown = true;
        _sub?.cancel();
        _showGameOver("ホストが不在になったため、この部屋は閉鎖されました。");
        return;
      }

      if (isHost && moriPhase == 'mori_declared') {
        if (_lastTrackedMoriPlayer != lastMoriPlayerId) {
          _lastTrackedMoriPlayer = lastMoriPlayerId ?? '';
          _moriTimer?.cancel();
          _moriTimer = Timer(const Duration(seconds: 5), () {
            _db.updateGameStatus({'moriPhase': 'finished'});
          });
        }
      }

      if (moriPhase == 'finished' && lastMoriPlayerId != null) {
        _moriTimer?.cancel();
        _showGameOver(lastMoriPlayerId == myId ? "勝利！(もり成功)" : 
                      (loserPlayerId == myId ? "敗北...(もりを宣言されました)" : "ゲーム終了"));
      }

      if (data['winnerId'] != null) {
        _showGameOver(data['winnerId'] == myId ? "勝利！" : "敗北...");
      }
    });
  }

  // 正常な画面離脱時（戻るボタンなど）の処理
  void _cleanupRoomOnLeave() {
    if (isHost) {
      _closeRoomForcefully();
    } else {
      // ゲストが抜ける場合は、プレイヤーリストから自分を消すだけ
      List<String> updatedPlayers = List<String>.from(playerIds)..remove(myId);
      _db.updateGameStatus({
        'players': updatedPlayers,
        'playerHands/$myId': null // 手札データも削除
      });
    }
  }

  // 部屋を強制閉鎖する内部メソッド
  void _closeRoomForcefully() {
    _db.updateGameStatus({'roomStatus': 'closed'});
    // 数秒後にノード自体を完全に削除してクリーンアップ（任意）
    Timer(const Duration(seconds: 2), () {
      FirebaseDatabase.instance.ref('rooms/${widget.roomId}').remove();
    });
  }

  void _onCardTap(int index) {
    if (moriPhase == 'mori_declared') return;

    final card = myHand[index];
    int myIdx = playerIds.indexOf(myId);
    bool isMyTurn = (currentTurn % playerIds.length == myIdx);
    
    bool isJokerField = (fieldSuit == Suit.joker);
    bool isInterrupt = (!isMyTurn && card.number == fieldNumber && fieldNumber != -1);
    bool canPlayInTurn = isMyTurn && GameRules.canPlayNormal(fieldNumber, fieldSuit, card);

    if (canPlayInTurn || isInterrupt || isJokerField) {
      _executePlay([card]);
    }
  }

  void _onMori() {
    if (GameRules.isValidMori(fieldNumber, myHand)) {
      if (moriPhase == 'none') {
        if (lastPlayerId == myId) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自滅はできません！')));
          return;
        }
        _db.updateGameStatus({
          'moriPhase': 'mori_declared',
          'lastMoriPlayerId': myId,
          'loserPlayerId': lastPlayerId
        });
      } else if (moriPhase == 'mori_declared') {
        _db.updateGameStatus({
          'lastMoriPlayerId': myId,
          'loserPlayerId': lastMoriPlayerId,
        });
      }
      _executePlay(myHand, isMoriAction: true);
    }
  }

  void _onDraw() {
    if (deck.isEmpty || moriPhase == 'mori_declared') return;
    
    final drawn = deck.last;
    bool canPlayDrawnCard = GameRules.canPlayNormal(fieldNumber, fieldSuit, drawn);
    
    if (GameRules.isBurst(myHand.length + 1, canPlayDrawnCard)) {
      _db.updateGameStatus({'winnerId': 'other_players'});
      _showGameOver("バースト！手札が7枚になり、出せるカードがありません。");
      return;
    }

    setState(() {
      myHand.add(drawn);
    });

    _db.updateGameStatus({
      'deck': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'playerHands/$myId': myHand.length,
      'currentTurnIndex': (currentTurn + 1) % playerIds.length, 
    });
  }

  void _executePlay(List<CardWidget> cards, {bool isMoriAction = false}) {
    if (cards.isEmpty) return;
    final lastCard = cards.last;
    int myIdx = playerIds.indexOf(myId);
    int nextTurnIndex = (myIdx + 1) % playerIds.length;

    setState(() {
      for (var c in cards) {
        myHand.removeWhere((h) => h.number == c.number && h.suit == c.suit);
      }
    });

    Map<String, dynamic> updates = {
      'field': {'number': lastCard.number, 'suit': lastCard.suit.name},
      'playerHands/$myId': myHand.length,
    };

    if (!isMoriAction) {
      updates['lastPlayerId'] = myId;
      updates['currentTurnIndex'] = nextTurnIndex;
      updates['isInitialPhase'] = false;
      updates['gameStarted'] = true;
    }

    _db.updateGameStatus(updates);

    if (myHand.isEmpty && !isMoriAction) {
      _db.updateGameStatus({'winnerId': myId});
    }
  }

  void _onFlip() {
    if (!isHost || deck.isEmpty) return;
    final flippedCard = deck.last;
    final newDeck = deck.sublist(0, deck.length - 1);

    _db.updateGameStatus({
      'field': {'number': flippedCard.number, 'suit': flippedCard.suit.name},
      'deck': newDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'isInitialPhase': true, 
      'lastPlayerId': 'system',
      'gameStarted': true,
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
            onPressed: () {
              _moriTimer?.cancel();
              Navigator.popUntil(context, (r) => r.isFirst);
            }, 
            child: const Text("ロビーへ")
          )
        ]
      )
    );
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("入室エラー"),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("戻る"))],
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return GameBoardView(
      roomId: widget.roomId, fieldNumber: fieldNumber, fieldSuit: fieldSuit,
      myHand: myHand, playerIds: playerIds, myId: myId, handCounts: handCounts, 
      currentTurnIndex: currentTurn, isHost: isHost, lastPlayerId: lastPlayerId, 
      isInitialPhase: isInitialPhase, moriPhase: moriPhase, 
      onCardTap: _onCardTap, onMori: _onMori, onDraw: _onDraw, onFlip: _onFlip,
    );
  }
}