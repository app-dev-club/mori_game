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

  String moriPhase = 'none'; 
  String? lastMoriPlayerId, loserPlayerId;     
  Timer? _moriTimer;         
  String _lastTrackedMoriPlayer = ''; 
  bool hasDeclaredMori = false;
  String roomStatus = 'open'; 
  bool _isClosedDialogShown = false;

  // 直前にカードを引いたプレイヤーのIDを管理
  String? lastDrawerId;

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
    if (isHost && (state == AppLifecycleState.paused || state == AppLifecycleState.detached)) _closeRoomForcefully();
  }

  Future<void> _init() async {
    final snap = await _db.getSnapshot();
    if (!snap.exists) {
      List<CardWidget> fullDeck = _generateDeck()..shuffle();
      final hand = fullDeck.sublist(0, 5);
      fullDeck.removeRange(0, 5);
      await _db.setupRoom(myId, fullDeck, widget.isPrivate);
      FirebaseDatabase.instance.ref('rooms/${widget.roomId}').onDisconnect().update({'roomStatus': 'closed'});
      setState(() => myHand = hand);
    } else {
      bool isStarted = snap.child('gameStarted').value == true;
      String currentStatus = snap.child('roomStatus').value as String? ?? 'open';
      if (isStarted || currentStatus == 'closed') {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showErrorDialog("このゲームは既に開始されているか、閉鎖されているため入室できません。"));
        return;
      }
      List<String> p = snap.child('players').exists ? List<String>.from(snap.child('players').value as List) : [];
      if (!p.contains(myId)) p.add(myId);
      List<dynamic> rawDeck = snap.child('deck').value as List<dynamic>? ?? [];
      List<CardWidget> cDeck = rawDeck.map((i) => CardWidget(number: i['number'], suit: Suit.values.firstWhere((e) => e.name == i['suit']))).toList();
      List<CardWidget> iHand = [];
      for (int i = 0; i < 5; i++) { if (cDeck.isNotEmpty) iHand.add(cDeck.removeLast()); }
      await _db.updateGameStatus({'players': p, 'playerHands/$myId': iHand.length, 'deck': cDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList()});
      setState(() => myHand = iHand);
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
      
      lastDrawerId = data['lastDrawerId'];

      if (data['playerHands'] != null) handCounts = Map<String, int>.from(data['playerHands']);
      if (data['field'] != null) {
        fieldNumber = data['field']['number'];
        fieldSuit = Suit.values.firstWhere((e) => e.name == data['field']['suit'], orElse: () => Suit.joker);
      }
      if (data['deck'] != null) deck = (data['deck'] as List).map((i) => CardWidget(number: i['number'], suit: Suit.values.firstWhere((e) => e.name == i['suit']))).toList();
      isInitialPhase = data['isInitialPhase'] ?? true;
      moriPhase = data['moriPhase'] ?? 'none';
      lastMoriPlayerId = data['lastMoriPlayerId'];
      loserPlayerId = data['loserPlayerId'];
      if (moriPhase == 'none') hasDeclaredMori = false;
      if (roomStatus == 'closed' && !isHost && !_isClosedDialogShown) { _isClosedDialogShown = true; _sub?.cancel(); _showGameOver("ホスト不在のため閉鎖されました"); }
      if (isHost && moriPhase == 'mori_declared' && _lastTrackedMoriPlayer != lastMoriPlayerId) {
        _lastTrackedMoriPlayer = lastMoriPlayerId ?? '';
        _moriTimer?.cancel();
        _moriTimer = Timer(const Duration(seconds: 5), () => _db.updateGameStatus({'moriPhase': 'finished'}));
      }
      if (moriPhase == 'finished' && lastMoriPlayerId != null) { _moriTimer?.cancel(); _showGameOver(lastMoriPlayerId == myId ? "勝利！(もり成功)" : (loserPlayerId == myId ? "敗北...(もりを宣言されました)" : "ゲーム終了")); }
      if (data['winnerId'] != null) _showGameOver(data['winnerId'] == myId ? "勝利！" : "敗北...");
    });
  }

  void _onCardTap(int index) {
    if (moriPhase == 'mori_declared') return;
    final card = myHand[index];
    int myIdx = playerIds.indexOf(myId);
    
    bool isServerTurn = (currentTurn % playerIds.length == myIdx);
    bool isLastDrawer = (lastDrawerId == myId); 
    bool isInterrupt = (card.number == fieldNumber && fieldNumber != -1);
    bool isJokerField = (fieldSuit == Suit.joker);

    if (isServerTurn || isLastDrawer || isInterrupt || isJokerField) {
      if (GameRules.canPlayNormal(fieldNumber, fieldSuit, card) || isInterrupt || isJokerField) {
        _executePlay([card]);
      }
    }
  }

  void _onDraw() {
    if (deck.isEmpty || moriPhase != 'none' || isInitialPhase) return;
    int myIdx = playerIds.indexOf(myId);
    if (currentTurn % playerIds.length != myIdx) return;

    final drawn = deck.last;
    
    List<CardWidget> tempHand = List.from(myHand)..add(drawn);
    bool hasPlayableCard = tempHand.any((c) => GameRules.canPlayNormal(fieldNumber, fieldSuit, c));

    if (tempHand.length >= 7 && !hasPlayableCard) { 
      _db.updateGameStatus({'winnerId': 'other_players'}); 
      _showGameOver("バースト！手札が7枚になり、出せるカードがありません。");
      return; 
    }

    setState(() { myHand.add(drawn); });

    _db.updateGameStatus({
      'deck': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'playerHands/$myId': myHand.length,
      'currentTurnIndex': (myIdx + 1) % playerIds.length,
      'lastDrawerId': myId,
    });
  }

  void _executePlay(List<CardWidget> cards) {
    if (cards.isEmpty) return;
    int myIdx = playerIds.indexOf(myId);
    setState(() { for (var c in cards) { myHand.removeWhere((h) => h.number == c.number && h.suit == c.suit); } });
    
    _db.updateGameStatus({
      'field': {'number': cards.last.number, 'suit': cards.last.suit.name},
      'playerHands/$myId': myHand.length,
      'lastPlayerId': myId,
      'currentTurnIndex': (myIdx + 1) % playerIds.length, 
      'lastDrawerId': null, 
      'isInitialPhase': false, 
      'gameStarted': true,
    });
    
    // 【修正箇所】 手札が0枚になった場合の自動勝利判定（winnerIdの更新）を削除しました。
    // 手札が0枚になっても、勝つためには「もり」の宣言が必須となります。
  }

  void _onMori() {
    if (!GameRules.isValidMori(fieldNumber, myHand)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('計算が合いません！'))); return; }
    setState(() => hasDeclaredMori = true);
    if (moriPhase == 'none') {
      if (lastPlayerId == myId) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自滅はできません！'))); setState(() => hasDeclaredMori = false); return; }
      _db.updateGameStatus({'moriPhase': 'mori_declared', 'lastMoriPlayerId': myId, 'loserPlayerId': lastPlayerId});
    } else {
      _db.updateGameStatus({'lastMoriPlayerId': myId, 'loserPlayerId': lastMoriPlayerId});
    }
  }

  void _onFlip() {
    if (!isHost || deck.isEmpty) return;
    final card = deck.last;
    _db.updateGameStatus({'field': {'number': card.number, 'suit': card.suit.name}, 'deck': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(), 'isInitialPhase': true, 'lastPlayerId': 'system', 'gameStarted': true});
  }

  void _cleanupRoomOnLeave() {
    if (isHost) _closeRoomForcefully();
    else { List<String> p = List<String>.from(playerIds)..remove(myId); _db.updateGameStatus({'players': p, 'playerHands/$myId': null}); }
  }

  void _closeRoomForcefully() { _db.updateGameStatus({'roomStatus': 'closed'}); Timer(const Duration(seconds: 2), () => FirebaseDatabase.instance.ref('rooms/${widget.roomId}').remove()); }

  List<CardWidget> _generateDeck() { return [for (var s in Suit.values) if (s != Suit.joker) for (var i = 1; i <= 13; i++) CardWidget(number: i, suit: s), const CardWidget(number: 0, suit: Suit.joker)]; }

  void _showGameOver(String msg) { showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(title: Text(msg), actions: [TextButton(onPressed: () => Navigator.popUntil(context, (r) => r.isFirst), child: const Text("ロビーへ"))])); }

  void _showErrorDialog(String msg) { showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(title: const Text("入室エラー"), content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("戻る"))])); }

  @override
  Widget build(BuildContext context) {
    return GameBoardView(
      roomId: widget.roomId, fieldNumber: fieldNumber, fieldSuit: fieldSuit, myHand: myHand, playerIds: playerIds, myId: myId,
      handCounts: handCounts, currentTurnIndex: currentTurn, isHost: isHost, lastPlayerId: lastPlayerId, isInitialPhase: isInitialPhase,
      moriPhase: moriPhase, hasDeclaredMori: hasDeclaredMori, onCardTap: _onCardTap, onMori: _onMori, onDraw: _onDraw, onFlip: _onFlip,
    );
  }
}