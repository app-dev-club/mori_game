import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../../services/firebase_db.dart';
import '../../logic/game_rules.dart';
import 'game_board_view.dart';

class GameRoomPage extends StatefulWidget {
  final String roomId;
  final bool isPrivate;
  final String playerName;
  const GameRoomPage({
    super.key,
    required this.roomId,
    this.isPrivate = false,
    required this.playerName,
  });
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
  Map<String, String> playerNames = {};
  Map<String, int> handCounts = {};
  int fieldNumber = -1;
  Suit fieldSuit = Suit.joker;
  int currentTurn = 0;
  bool isInitialPhase = true;
  String? lastPlayerId;
  List<CardWidget> deck = [];
  List<CardWidget> fieldHistory = [];

  String moriPhase = 'none'; 
  String? lastMoriPlayerId, loserPlayerId;
  List<CardWidget> moriRevealedHand = [];
  String? moriRevealedType;
  Timer? _moriTimer;         
  String _lastTrackedMoriPlayer = ''; 
  bool hasDeclaredMori = false;
  String roomStatus = 'open'; 
  bool _isClosedDialogShown = false;
  bool _gameOverDialogShown = false;
  bool _gameOverRouteOpen = false;
  int _lastRematchGeneration = 0;
  bool _rematchRestartInProgress = false;
  int _rematchReadyCount = 0;

  String? lastDrawerId;
  bool isDrawCompetitive = false;
  bool _hasPlayedThisTurn = false;
  int? _lastDeckResetAt;

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
      await _db.setupRoom(
        myId,
        fullDeck,
        widget.isPrivate,
        playerName: widget.playerName,
        deckIndex: _serializeHand(fullDeck),
        initialHand: _serializeHand(hand),
      );
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
      await _db.updateGameStatus({
        'players': p,
        'playerHands/$myId': iHand.length,
        'playerCards/$myId': _serializeHand(iHand),
        'playerNames/$myId': widget.playerName,
        'deck': cDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
        'deckIndex': cDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      });
      setState(() => myHand = iHand);
    }
    _sub = _db.roomStream.listen(_onData);
  }

  void _onData(DatabaseEvent event) {
    final data = event.snapshot.value as Map?;
    if (data == null || !mounted) return;
    final int? deckResetAt = data['deckResetAt'] as int?;
    final bool shouldNotifyDeckReset =
        deckResetAt != null && deckResetAt != _lastDeckResetAt;
    setState(() {
      hostId = data['host'];
      playerIds = List<String>.from(data['players'] ?? []);
      if (data['playerNames'] != null) {
        playerNames = Map<String, String>.from(
          (data['playerNames'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
      currentTurn = data['currentTurnIndex'] ?? 0;
      lastPlayerId = data['lastPlayerId'];
      roomStatus = data['roomStatus'] ?? 'open';
      
      lastDrawerId = data['lastDrawerId'];
      isDrawCompetitive = data['isDrawCompetitive'] == true;
      if (shouldNotifyDeckReset) _lastDeckResetAt = deckResetAt;

      final int myIdx = playerIds.indexOf(myId);
      final bool isMyTurn = playerIds.isNotEmpty && (currentTurn % playerIds.length == myIdx);
      final bool inDrawCompetition = GameRules.canPlayInDrawCompetition(
        isDrawCompetitive: isDrawCompetitive,
        lastDrawerId: lastDrawerId,
        players: playerIds,
        myId: myId,
      );
      if (inDrawCompetition) {
        _hasPlayedThisTurn = false;
      } else if (lastDrawerId == myId) {
        _hasPlayedThisTurn = false;
      } else if (isMyTurn && lastPlayerId != myId) {
        _hasPlayedThisTurn = false;
      }

      if (data['playerHands'] != null) handCounts = Map<String, int>.from(data['playerHands']);
      if (data['playerCards'] != null) {
        final playerCards = Map<String, dynamic>.from(data['playerCards'] as Map);
        final countsFromCards = <String, int>{};
        playerCards.forEach((pid, cards) {
          if (cards is List) countsFromCards[pid] = cards.length;
        });
        handCounts = {...handCounts, ...countsFromCards};
      }
      if (data['field'] != null) {
        fieldNumber = data['field']['number'];
        fieldSuit = Suit.values.firstWhere((e) => e.name == data['field']['suit'], orElse: () => Suit.joker);
      }
      if (data['deck'] != null) deck = (data['deck'] as List).map((i) => CardWidget(number: i['number'], suit: Suit.values.firstWhere((e) => e.name == i['suit']))).toList();

      if (data['fieldHistory'] != null) {
        fieldHistory = (data['fieldHistory'] as List)
            .map((i) => CardWidget(
                  number: i['number'],
                  suit: Suit.values.firstWhere((e) => e.name == i['suit']),
                ))
            .toList();
      } else if (fieldNumber != -1) {
        fieldHistory = [CardWidget(number: fieldNumber, suit: fieldSuit)];
      } else {
        fieldHistory = [];
      }

      // 既存ルーム互換: fieldHistory が無い場合、ホストが最小限の履歴をFirebaseへ作る
      if (isHost && data['fieldHistory'] == null && fieldNumber != -1) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _db.updateGameStatus({
            'fieldHistory': [
              {'number': fieldNumber, 'suit': fieldSuit.name}
            ],
          });
        });
      }
      if (isHost && data['deckIndex'] == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _db.updateGameStatus({
            'deckIndex': deck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
          });
        });
      }

      isInitialPhase = data['isInitialPhase'] ?? true;
      moriPhase = data['moriPhase'] ?? 'none';
      lastMoriPlayerId = data['lastMoriPlayerId'];
      loserPlayerId = data['loserPlayerId'];
      moriRevealedHand = _parseHandFromFirebase(data['moriRevealedHand']);
      moriRevealedType = data['moriRevealedType'] as String?;
      if (moriPhase == 'none') {
        hasDeclaredMori = false;
        moriRevealedHand = [];
        moriRevealedType = null;
      }
      
      if (roomStatus == 'closed' && !isHost && !_isClosedDialogShown) { 
        _isClosedDialogShown = true; 
        _sub?.cancel(); 
        _showGameOver("ホスト不在のため閉鎖されました"); 
      }
      
      if (isHost && moriPhase == 'mori_declared' && _lastTrackedMoriPlayer != lastMoriPlayerId) {
        _lastTrackedMoriPlayer = lastMoriPlayerId ?? '';
        _moriTimer?.cancel();
        _moriTimer = Timer(const Duration(seconds: 5), () => _db.updateGameStatus({'moriPhase': 'finished'}));
      }
      
      if (moriPhase == 'finished' && lastMoriPlayerId != null) { 
        _moriTimer?.cancel(); 
        _showGameOver(
          lastMoriPlayerId == myId
              ? "勝利！(もり成功)"
              : (loserPlayerId == myId
                  ? "敗北...（${_displayName(lastMoriPlayerId)}にもりを宣言されました）"
                  : "ゲーム終了"),
          allowRematch: true,
        ); 
      }

      String? burstPlayerId = data['burstPlayerId'];
      if (burstPlayerId != null) {
        if (burstPlayerId == myId) {
          _showGameOver("敗北（バースト）\n手札が7枚になり、出せるカードがありませんでした。", allowRematch: true);
        } else {
          _showGameOver(
            "ゲーム終了\n（${_displayName(burstPlayerId)}がバーストしたため、勝者はありません）",
            allowRematch: true,
          );
        }
      }

      _rematchReadyCount = _countRematchReady(data, playerIds);
      final int rematchGen = data['rematchGeneration'] as int? ?? 0;
      if (rematchGen > _lastRematchGeneration) {
        _lastRematchGeneration = rematchGen;
        _applyRematchHands(data);
        _gameOverDialogShown = false;
        _rematchRestartInProgress = false;
        if (_gameOverRouteOpen) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _gameOverRouteOpen) {
              Navigator.of(context).pop();
              _gameOverRouteOpen = false;
            }
          });
        }
      }

      if (isHost && !_rematchRestartInProgress && _allRematchReady(data, playerIds)) {
        _rematchRestartInProgress = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _hostRestartGame(List<String>.from(playerIds)));
      }
    });

    if (shouldNotifyDeckReset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('山札が尽きたのでシャッフルして補充しました')),
        );
      });
    }
  }

  void _onCardTap(int index) {
    if (moriPhase == 'mori_declared') return;
    if (fieldNumber == -1) return;

    final card = myHand[index];
    int myIdx = playerIds.indexOf(myId);

    final bool isJokerField = GameRules.isJokerOnField(fieldNumber, fieldSuit);

    if (isInitialPhase) {
      if (GameRules.canPlayNormal(fieldNumber, fieldSuit, card, isInitialPhase: true)) {
        _executePlay([card]);
      }
      return;
    }

    bool isServerTurn = (currentTurn % playerIds.length == myIdx);
    bool isLastDrawer = (lastDrawerId == myId);
    bool isCompetitiveParticipant = GameRules.canPlayInDrawCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: playerIds,
      myId: myId,
    );
    bool isInterrupt = (card.number == fieldNumber);
    final bool usesTurnPlayLimit = isServerTurn || isLastDrawer || isCompetitiveParticipant;

    if (usesTurnPlayLimit && _hasPlayedThisTurn && !isInterrupt && !isJokerField) return;

    if (isServerTurn || isLastDrawer || isCompetitiveParticipant || isInterrupt || isJokerField) {
      if (GameRules.canPlayNormal(fieldNumber, fieldSuit, card) || isInterrupt || isJokerField) {
        _executePlay([card]);
      }
    }
  }

  void _onDraw() {
    if (moriPhase != 'none' || isInitialPhase) return;
    int myIdx = playerIds.indexOf(myId);
    final bool isScheduledTurn = currentTurn % playerIds.length == myIdx;
    final bool canDrawInCompetition = GameRules.canDrawInCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: playerIds,
      myId: myId,
      handCount: myHand.length,
    );
    if (!isScheduledTurn && !canDrawInCompetition) return;
    if (!GameRules.canDraw(myHand.length, lastDrawerId, myId)) return;

    // 山札が尽きた場合：場の最新カード以外を戻してシャッフル
    if (deck.isEmpty) {
      _replenishDeckFromFieldIfEmpty();
      if (deck.isEmpty) return;
    }

    final drawn = deck.last;
    
    List<CardWidget> tempHand = List.from(myHand)..add(drawn);
    bool hasPlayableCard = tempHand.any((c) => GameRules.canPlayNormal(fieldNumber, fieldSuit, c));

    List<CardWidget> deckAfterDrawCards = deck.sublist(0, deck.length - 1);
    final resetMetaUpdates = <String, dynamic>{};
    if (deckAfterDrawCards.isEmpty) {
      final replenished = _rebuildDeckFromFieldHistoryWithoutLatest();
      if (replenished.isNotEmpty) {
        deckAfterDrawCards = replenished;
        resetMetaUpdates.addAll({
          'field': {'number': fieldNumber, 'suit': fieldSuit.name},
          'fieldHistory': fieldHistory.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
          'deckResetAt': ServerValue.timestamp,
        });
      }
    }
    final deckAfterDraw =
        deckAfterDrawCards.map((c) => {'number': c.number, 'suit': c.suit.name}).toList();
    final bool isSeventhDraw = tempHand.length >= 7;

    // 7枚目で出せるカードがなければバースト
    if (GameRules.isBurst(tempHand.length, hasPlayableCard)) {
      setState(() => myHand.add(drawn));
      _db.updateGameStatus({
        'burstPlayerId': myId,
        'deck': deckAfterDraw,
        'deckIndex': deckAfterDraw,
        'playerHands/$myId': myHand.length,
        'playerCards/$myId': _serializeHand(myHand),
        'currentTurnIndex': myIdx,
        'lastDrawerId': null,
        'isDrawCompetitive': false,
        ...resetMetaUpdates,
      });
      return;
    }

    setState(() => myHand.add(drawn));

    // 手札6枚以下: 次のプレイヤーも出す/引く権利（早い者勝ち）。7枚目は競合なし。
    final bool enableDrawCompetition = !isSeventhDraw;
    _db.updateGameStatus({
      'deck': deckAfterDraw,
      'deckIndex': deckAfterDraw,
      'playerHands/$myId': myHand.length,
      'playerCards/$myId': _serializeHand(myHand),
      if (isSeventhDraw) ...{
        'currentTurnIndex': myIdx,
        'lastDrawerId': myId,
        'isDrawCompetitive': false,
      } else ...{
        'currentTurnIndex': (myIdx + 1) % playerIds.length,
        'lastDrawerId': myId,
        'isDrawCompetitive': enableDrawCompetition,
      },
      ...resetMetaUpdates,
    });
  }

  List<CardWidget> _rebuildDeckFromFieldHistoryWithoutLatest() {
    if (fieldHistory.length <= 2) return [];
    final latest = fieldHistory.last;
    final rebuilt = List<CardWidget>.from(fieldHistory)..removeLast();
    rebuilt.shuffle();
    fieldNumber = latest.number;
    fieldSuit = latest.suit;
    fieldHistory = [latest];
    return rebuilt;
  }

  void _executePlay(List<CardWidget> cards) {
    if (cards.isEmpty) return;
    int myIdx = playerIds.indexOf(myId);
    _hasPlayedThisTurn = true;
    setState(() { for (var c in cards) { myHand.removeWhere((h) => h.number == c.number && h.suit == c.suit); } });

    final CardWidget playedCard = cards.last;
    final updatedHistory = List<CardWidget>.from(fieldHistory)..add(playedCard);
    fieldHistory = updatedHistory;

    _db.updateGameStatus({
      'field': {'number': playedCard.number, 'suit': playedCard.suit.name},
      'playerHands/$myId': myHand.length,
      'playerCards/$myId': _serializeHand(myHand),
      'lastPlayerId': myId,
      'currentTurnIndex': (myIdx + 1) % playerIds.length,
      'lastDrawerId': null,
      'isDrawCompetitive': false,
      'isInitialPhase': false,
      'gameStarted': true,
      'fieldHistory': updatedHistory.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
    });
  }

  void _onMori() {
    if (!GameRules.isValidMori(fieldNumber, myHand)) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('計算が合いません！'))); return; }
    setState(() => hasDeclaredMori = true);
    final revealedHand = _serializeHand(myHand);
    if (moriPhase == 'none') {
      if (lastPlayerId == myId) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('自滅はできません！'))); setState(() => hasDeclaredMori = false); return; }
      _db.updateGameStatus({
        'moriPhase': 'mori_declared',
        'lastMoriPlayerId': myId,
        'loserPlayerId': lastPlayerId,
        'moriRevealedHand': revealedHand,
        'moriRevealedType': 'mori',
      });
    } else {
      _db.updateGameStatus({
        'lastMoriPlayerId': myId,
        'loserPlayerId': lastMoriPlayerId,
        'moriRevealedHand': revealedHand,
        'moriRevealedType': 'gaeshi',
      });
    }
  }

  List<Map<String, dynamic>> _serializeHand(List<CardWidget> hand) =>
      hand.map((c) => {'number': c.number, 'suit': c.suit.name}).toList();

  List<CardWidget> _parseHandFromFirebase(dynamic raw) {
    if (raw == null) return [];
    return (raw as List)
        .map((i) => CardWidget(
              number: i['number'] as int,
              suit: Suit.values.firstWhere((e) => e.name == i['suit']),
            ))
        .toList();
  }

  void _onFlip() {
    if (!isHost) return;
    if (deck.isEmpty) {
      _replenishDeckFromFieldIfEmpty();
      if (deck.isEmpty) return;
    }
    final card = deck.last;
    final updatedHistory = List<CardWidget>.from(fieldHistory)..add(card);
    fieldHistory = updatedHistory;
    _db.updateGameStatus({
      'field': {'number': card.number, 'suit': card.suit.name},
      'deck': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'deckIndex': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'fieldHistory': updatedHistory.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'isInitialPhase': true,
      'lastPlayerId': 'system',
      'gameStarted': true,
    });
  }

  /// 山札が空のときだけ、場の履歴から「最新カード以外」を山札に戻してシャッフルします。
  void _replenishDeckFromFieldIfEmpty() {
    if (deck.isNotEmpty) return;

    // fieldHistory が無い/不足している状態で全54枚を再生成すると、手札にあるカードまで復活して重複する。
    // そのため、履歴が揃っていない場合は補充しない（ホストが履歴を作ってから再試行）。
    // 山札化できる捨て札が1枚以下だと同じカードをループしやすいため、補充しない。
    if (fieldHistory.length <= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('山札を補充できません（捨て札が不足しています）')),
        );
      });
      return;
    }

    final CardWidget latest = fieldHistory.last;
    final discardPile = List<CardWidget>.from(fieldHistory)..removeLast();
    discardPile.shuffle();

    deck = discardPile;
    fieldNumber = latest.number;
    fieldSuit = latest.suit;
    fieldHistory = [latest];

    _db.updateGameStatus({
      'deck': deck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'deckIndex': deck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'field': {'number': latest.number, 'suit': latest.suit.name},
      'fieldHistory': [
        {'number': latest.number, 'suit': latest.suit.name},
      ],
      'deckResetAt': ServerValue.timestamp,
    });
  }

  void _cleanupRoomOnLeave() {
    if (isHost) {
      _closeRoomForcefully();
    } else {
      List<String> p = List<String>.from(playerIds)..remove(myId);
      _db.updateGameStatus({
        'players': p,
        'playerHands/$myId': null,
        'playerCards/$myId': null,
        'playerNames/$myId': null,
      });
    }
  }

  void _closeRoomForcefully() { _db.updateGameStatus({'roomStatus': 'closed'}); Timer(const Duration(seconds: 2), () => FirebaseDatabase.instance.ref('rooms/${widget.roomId}').remove()); }

  /// 各スート(♠♥♦♣)で1-13が各1枚ずつ(52枚) + ジョーカー2枚 = 54枚
  List<CardWidget> _generateDeck() {
    const nonJokerSuits = <Suit>[Suit.spade, Suit.heart, Suit.diamond, Suit.club];
    return [
      for (final s in nonJokerSuits)
        for (var i = 1; i <= 13; i++) CardWidget(number: i, suit: s),
      const CardWidget(number: 0, suit: Suit.joker),
      const CardWidget(number: 0, suit: Suit.joker),
    ];
  }

  int _countRematchReady(Map data, List<String> players) {
    if (players.isEmpty) return 0;
    final ready = data['rematchReady'];
    if (ready == null) return 0;
    final readyMap = Map<String, dynamic>.from(ready as Map);
    return players.where((p) => readyMap[p] == true).length;
  }

  bool _allRematchReady(Map data, List<String> players) {
    if (players.isEmpty) return false;
    return _countRematchReady(data, players) >= players.length;
  }

  void _applyRematchHands(Map data) {
    final raw = data['rematchHands'];
    if (raw is! Map || raw[myId] == null) return;
    myHand = (raw[myId] as List)
        .map((i) => CardWidget(
              number: i['number'] as int,
              suit: Suit.values.firstWhere((e) => e.name == i['suit']),
            ))
        .toList();
    _hasPlayedThisTurn = false;
    _lastTrackedMoriPlayer = '';
    hasDeclaredMori = false;
  }

  Future<void> _hostRestartGame(List<String> players) async {
    if (players.isEmpty) {
      _rematchRestartInProgress = false;
      return;
    }
    final snap = await _db.getSnapshot();
    final nextGen = (snap.child('rematchGeneration').value as int? ?? 0) + 1;

    List<CardWidget> deck = _generateDeck()..shuffle();
    final rematchHands = <String, List<Map<String, dynamic>>>{};
    for (final pid in players) {
      final hand = <CardWidget>[];
      for (int i = 0; i < 5; i++) {
        if (deck.isNotEmpty) hand.add(deck.removeLast());
      }
      rematchHands[pid] = hand.map((c) => {'number': c.number, 'suit': c.suit.name}).toList();
    }
    final remainingDeck = deck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList();

    await _db.restartGame(
      players: players,
      rematchHands: rematchHands,
      remainingDeck: remainingDeck,
      deckIndex: remainingDeck,
      rematchGeneration: nextGen,
    );
    if (mounted) {
      setState(() {
        myHand = (rematchHands[myId] ?? [])
            .map((i) => CardWidget(
                  number: i['number'] as int,
                  suit: Suit.values.firstWhere((e) => e.name == i['suit']),
                ))
            .toList();
      });
    }
    _rematchRestartInProgress = false;
  }

  Future<void> _onRematchRequest() async {
    await _db.setRematchReady(myId);
    if (!mounted) return;
    if (_gameOverRouteOpen) {
      Navigator.of(context).pop();
      _gameOverRouteOpen = false;
    }
    _gameOverDialogShown = false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('再戦の準備ができました。他のプレイヤーを待っています…')),
    );
  }

  void _showGameOver(String msg, {bool allowRematch = false}) {
    if (_gameOverDialogShown) return;
    _gameOverDialogShown = true;
    _gameOverRouteOpen = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(msg),
        content: allowRematch
            ? Text('再戦: $_rematchReadyCount / ${playerIds.length} 人が準備完了')
            : null,
        actions: [
          if (allowRematch)
            TextButton(
              onPressed: () => _onRematchRequest(),
              child: const Text('もう一度遊ぶ'),
            ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _gameOverRouteOpen = false;
              _gameOverDialogShown = false;
              Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: const Text('ロビーへ'),
          ),
        ],
      ),
    ).then((_) {
      _gameOverRouteOpen = false;
      _gameOverDialogShown = false;
    });
  }

  String _displayName(String? playerId) {
    if (playerId == null) return '不明';
    if (playerId == myId) return 'あなた';
    final name = playerNames[playerId];
    if (name != null && name.isNotEmpty) return name;
    final idx = playerIds.indexOf(playerId);
    return idx >= 0 ? 'プレイヤー${idx + 1}' : '不明';
  }

  void _showErrorDialog(String msg) { showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(title: const Text("入室エラー"), content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("戻る"))])); }

  @override
  Widget build(BuildContext context) {
    return GameBoardView(
      roomId: widget.roomId, fieldNumber: fieldNumber, fieldSuit: fieldSuit, myHand: myHand, playerIds: playerIds, myId: myId,
      playerNames: playerNames,
      handCounts: handCounts, currentTurnIndex: currentTurn, isHost: isHost, hostId: hostId, lastPlayerId: lastPlayerId, isInitialPhase: isInitialPhase,
      moriPhase: moriPhase, hasDeclaredMori: hasDeclaredMori, lastDrawerId: lastDrawerId, isDrawCompetitive: isDrawCompetitive,
      lastMoriPlayerId: lastMoriPlayerId, moriRevealedHand: moriRevealedHand, moriRevealedType: moriRevealedType,
      rematchReadyCount: _rematchReadyCount, playerCount: playerIds.length,
      onCardTap: _onCardTap, onMori: _onMori, onDraw: _onDraw, onFlip: _onFlip,
    );
  }
}