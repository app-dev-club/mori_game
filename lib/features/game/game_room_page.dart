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

  // ドローした直後のカードを記憶（早い者勝ちで出すため）
  CardWidget? _justDrawnCard;

  // もりシステム用
  String moriPhase = 'none'; 
  String? lastMoriPlayerId;  
  String? loserPlayerId;     
  Timer? _moriTimer;         
  String _lastTrackedMoriPlayer = ''; 

  bool hasDeclaredMori = false;
  String roomStatus = 'open'; 
  bool _isClosedDialogShown = false;

  bool get isHost => myId == hostId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _db = FirebaseDB(widget.roomId);
    _init();
  }

  @override
  void dispose() {
    _cleanupRoomOnLeave(); 
    WidgetsBinding.instance.removeObserver(this); 
    _sub?.cancel();
    _moriTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isHost && (state == AppLifecycleState.paused || state == AppLifecycleState.detached)) {
      _closeRoomForcefully();
    }
  }

  Future<void> _init() async {
    final snap = await _db.getSnapshot();
    if (!snap.exists) {
      List<CardWidget> fullDeck = _generateDeck()..shuffle();
      final hand = fullDeck.sublist(0, 5);
      fullDeck.removeRange(0, 5);
      
      await _db.setupRoom(myId, fullDeck, widget.isPrivate);
      
      final roomRef = FirebaseDatabase.instance.ref('rooms/${widget.roomId}');
      await roomRef.onDisconnect().update({'roomStatus': 'closed'});

      setState(() => myHand = hand);
    } else {
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
        int newFieldNumber = data['field']['number'];
        Suit newFieldSuit = Suit.values.firstWhere((e) => e.name == data['field']['suit'], orElse: () => Suit.joker);
        
        // 誰かがカードを出して場が更新されたら、ドロー直後のカードを出す権利（ワンチャンス）をリセット
        if (fieldNumber != -1 && (fieldNumber != newFieldNumber || fieldSuit != newFieldSuit)) {
          _justDrawnCard = null;
        }

        fieldNumber = newFieldNumber;
        fieldSuit = newFieldSuit;
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

      if (moriPhase == 'none') {
        hasDeclaredMori = false;
      }

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

  void _cleanupRoomOnLeave() {
    if (isHost) {
      _closeRoomForcefully();
    } else {
      List<String> updatedPlayers = List<String>.from(playerIds)..remove(myId);
      _db.updateGameStatus({
        'players': updatedPlayers,
        'playerHands/$myId': null 
      });
    }
  }

  void _closeRoomForcefully() {
    _db.updateGameStatus({'roomStatus': 'closed'});
    Timer(const Duration(seconds: 2), () {
      FirebaseDatabase.instance.ref('rooms/${widget.roomId}').remove();
    });
  }

  // --- カードタップ処理 ---
  void _onCardTap(int index) {
    if (moriPhase == 'mori_declared') return;

    final card = myHand[index];
    int myIdx = playerIds.indexOf(myId);
    bool isMyTurn = (currentTurn % playerIds.length == myIdx);
    
    bool isJokerField = (fieldSuit == Suit.joker);
    bool isInterrupt = (!isMyTurn && card.number == fieldNumber && fieldNumber != -1);
    bool canPlayInTurn = isMyTurn && GameRules.canPlayNormal(fieldNumber, fieldSuit, card);

    // 【修正箇所】自分が直前にドローしたカードなら、ターンが移った後でも特別に出せる（早い者勝ち）
    bool canPlayJustDrawn = (_justDrawnCard != null && 
                             card.number == _justDrawnCard!.number && 
                             card.suit == _justDrawnCard!.suit && 
                             GameRules.canPlayNormal(fieldNumber, fieldSuit, card));

    if (canPlayInTurn || isInterrupt || isJokerField || canPlayJustDrawn) {
      _executePlay([card]);
      _justDrawnCard = null; // 出したら優先権をリセット
    }
  }

  // --- ドロー処理 ---
  void _onDraw() {
    if (deck.isEmpty || moriPhase == 'mori_declared') return;
    
    // 1. ゲーム開始前はドロー不可
    if (isInitialPhase) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ゲーム開始前は引けません！')));
      return;
    }

    // 2. 自分のターンのみドロー可能
    int myIdx = playerIds.indexOf(myId);
    bool isMyTurn = (currentTurn % playerIds.length == myIdx);
    if (!isMyTurn) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自分のターンのみ引けます！')));
      return;
    }

    final drawn = deck.last;
    bool canPlayDrawnCard = GameRules.canPlayNormal(fieldNumber, fieldSuit, drawn);
    
    if (GameRules.isBurst(myHand.length + 1, canPlayDrawnCard)) {
      _db.updateGameStatus({'winnerId': 'other_players'});
      _showGameOver("バースト！手札が7枚になり、出せるカードがありません。");
      return;
    }

    setState(() {
      myHand.add(drawn);
      _justDrawnCard = drawn; // 引いたカードを一時記憶
    });

    // 3. ドローした瞬間にターンを次に移す（連打防止 ＆ 次の人の早い者勝ち発生）
    _db.updateGameStatus({
      'deck': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'playerHands/$myId': myHand.length,
      'currentTurnIndex': (currentTurn + 1) % playerIds.length, 
    });
  }

  void _onMori() {
    if (GameRules.isValidMori(fieldNumber, myHand)) {
      setState(() {
        hasDeclaredMori = true;
      });

      if (moriPhase == 'none') {
        if (lastPlayerId == myId) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自滅はできません！')));
          setState(() { hasDeclaredMori = false; });
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
    }
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
      hasDeclaredMori: hasDeclaredMori, 
      onCardTap: _onCardTap, onMori: _onMori, onDraw: _onDraw, onFlip: _onFlip,
    );
  }
}