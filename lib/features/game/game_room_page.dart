import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import '../../services/firebase_db.dart';
import '../../logic/game_rules.dart';
import '../../logic/bot_logic.dart';
import '../../logic/room_config.dart';
import 'game_board_view.dart';

class GameRoomPage extends StatefulWidget {
  final String roomId;
  final bool isPrivate;
  final String playerName;
  final int? maxPlayers;
  const GameRoomPage({
    super.key,
    required this.roomId,
    this.isPrivate = false,
    required this.playerName,
    this.maxPlayers,
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
  bool _isIntentionalLeave = false;
  bool _postGameClosing = false;
  String? _postGameMessage;
  bool _postGameEntered = false;
  Timer? _hostDecisionTimer;
  Timer? _postGameCountdownTimer;
  Timer? _guestStayCountdownTimer;
  int? _countdownSeconds;
  int? _guestCountdownSeconds;
  bool rematchHostRequested = false;
  bool awaitingGuestStayResponses = false;
  List<String> rematchEligiblePlayers = [];
  Map<String, bool> rematchReadyMap = {};
  int? rematchStartedAt;
  bool myStayResponseSubmitted = false;
  bool _rematchFinalizing = false;
  int? postGameEndedAt;
  bool postGameActive = false;
  int maxPlayers = RoomConfig.defaultMaxPlayers;
  bool gameStarted = false;

  String? lastDrawerId;
  bool isDrawCompetitive = false;
  bool _hasPlayedThisTurn = false;
  int? _lastDeckResetAt;
  String? _statusMessage;
  Timer? _statusMessageTimer;
  Timer? _autoPlayTimer;
  Timer? _autoPlayCountdownTimer;
  String _autoPlayTimerKey = '';
  int? _autoPlayDeadlineMs;
  int? _autoPlayCountdownSeconds;
  Timer? _initialPhaseAutoFlipTimer;
  String _initialPhaseAutoFlipKey = '';
  Map<String, List<CardWidget>> _allPlayerCards = {};
  final Map<String, bool> _botHasPlayedThisTurn = {};
  final Map<String, Timer> _botTimers = {};
  final Map<String, String> _botTimerKeys = {};

  bool get isHost => myId == hostId;

  bool get _isActiveGameplay =>
      gameStarted && !postGameActive && !awaitingGuestStayResponses;

  bool get _showPostGameOverlay =>
      _postGameMessage != null &&
      (postGameActive || awaitingGuestStayResponses || (_postGameEntered && !_isActiveGameplay));

  void _showGameMessage(String message) {
    _statusMessageTimer?.cancel();
    setState(() => _statusMessage = message);
    _statusMessageTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _statusMessage = null);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); 
    _db = FirebaseDB(widget.roomId);
    _init();
  }

  @override
  void dispose() {
    if (!_isIntentionalLeave) _cleanupRoomOnLeave();
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _moriTimer?.cancel();
    _statusMessageTimer?.cancel();
    _hostDecisionTimer?.cancel();
    _postGameCountdownTimer?.cancel();
    _cancelGuestStayTimers();
    _cancelAutoPlayTimer();
    _cancelInitialPhaseAutoFlipTimer();
    _cancelAllBotTimers();
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
        maxPlayers: widget.maxPlayers ?? RoomConfig.defaultMaxPlayers,
        deckIndex: _serializeHand(fullDeck),
        initialHand: _serializeHand(hand),
      );
      maxPlayers = widget.maxPlayers ?? RoomConfig.defaultMaxPlayers;
      FirebaseDatabase.instance.ref('rooms/${widget.roomId}').onDisconnect().update({'roomStatus': 'closed'});
      setState(() => myHand = hand);
    } else {
      bool isStarted = snap.child('gameStarted').value == true;
      String currentStatus = snap.child('roomStatus').value as String? ?? 'open';
      if (currentStatus == 'closed' || isStarted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showErrorDialog("このゲームは既に開始されているか、閉鎖されているため入室できません。"));
        return;
      }
      List<String> p = snap.child('players').exists ? List<String>.from(snap.child('players').value as List) : [];
      maxPlayers = RoomConfig.resolveMaxPlayers(snap.child('maxPlayers').value);
      if (!p.contains(myId)) {
        if (RoomConfig.isRoomFull(p.length, maxPlayers)) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _showErrorDialog('このルームは定員（$maxPlayers人）に達しているため入室できません。'),
          );
          return;
        }
        p.add(myId);
      }
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
    if (data == null) {
      if (!mounted || _isIntentionalLeave || isHost) return;
      _forceReturnToLobby();
      return;
    }
    if (!mounted) return;
    final int? deckResetAt = data['deckResetAt'] as int?;
    final bool shouldNotifyDeckReset =
        deckResetAt != null && deckResetAt != _lastDeckResetAt;
    setState(() {
      hostId = data['host'];
      playerIds = List<String>.from(data['players'] ?? []);
      maxPlayers = RoomConfig.resolveMaxPlayers(data['maxPlayers']);
      gameStarted = data['gameStarted'] == true;
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
        final parsedAll = <String, List<CardWidget>>{};
        playerCards.forEach((pid, cards) {
          if (cards is List) {
            countsFromCards[pid.toString()] = cards.length;
            parsedAll[pid.toString()] = _parseHandFromFirebase(cards);
          }
        });
        if (isHost) _allPlayerCards = parsedAll;
        handCounts = {...handCounts, ...countsFromCards};
        if (playerCards[myId] is List) {
          myHand = parsedAll[myId] ?? _parseHandFromFirebase(playerCards[myId]);
        }
      }

      if (isHost) {
        for (final botId in playerIds.where(BotLogic.isBot)) {
          final botIdx = playerIds.indexOf(botId);
          final botMyTurn =
              playerIds.isNotEmpty && (currentTurn % playerIds.length == botIdx);
          final botInDrawCompetition = GameRules.canPlayInDrawCompetition(
            isDrawCompetitive: isDrawCompetitive,
            lastDrawerId: lastDrawerId,
            players: playerIds,
            myId: botId,
          );
          if (botInDrawCompetition || lastDrawerId == botId || (botMyTurn && lastPlayerId != botId)) {
            _botHasPlayedThisTurn[botId] = false;
          }
        }
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
      
      // 山札めくりやゲーム終了後の閉鎖では弾かない（ホスト切断時のロビー閉鎖のみ）
      if (roomStatus == 'closed' && !gameStarted && !postGameActive && !isHost && !_isClosedDialogShown) {
        _isClosedDialogShown = true;
        _sub?.cancel();
        _showGameOver("ホスト不在のため閉鎖されました");
      }
      
      if (isHost && moriPhase == 'mori_declared' && _lastTrackedMoriPlayer != lastMoriPlayerId) {
        _lastTrackedMoriPlayer = lastMoriPlayerId ?? '';
        _moriTimer?.cancel();
        _moriTimer = Timer(const Duration(seconds: 5), () => _db.updateGameStatus({'moriPhase': 'finished'}));
      }
      
      if (!_postGameEntered && moriPhase == 'finished' && lastMoriPlayerId != null) {
        _moriTimer?.cancel();
        _enterPostGame(
          lastMoriPlayerId == myId
              ? "勝利！(もり成功)"
              : (loserPlayerId == myId
                  ? "敗北...（${_displayName(lastMoriPlayerId)}にもりを宣言されました）"
                  : "ゲーム終了"),
        );
      }

      String? burstPlayerId = data['burstPlayerId'];
      if (!_postGameEntered && burstPlayerId != null) {
        if (burstPlayerId == myId) {
          _enterPostGame("敗北（バースト）\n手札が7枚になり、出せるカードがありませんでした。");
        } else {
          _enterPostGame(
            "ゲーム終了\n（${_displayName(burstPlayerId)}がバーストしたため、勝者はありません）",
          );
        }
      }

      postGameActive = data['postGameActive'] == true;
      rematchHostRequested = data['rematchHostRequested'] == true;
      awaitingGuestStayResponses = data['awaitingGuestStayResponses'] == true;
      rematchEligiblePlayers = List<String>.from(data['rematchEligiblePlayers'] ?? []);
      rematchStartedAt = data['rematchStartedAt'] as int?;
      if (data['rematchReady'] != null) {
        rematchReadyMap = Map<String, bool>.from(
          (data['rematchReady'] as Map).map((k, v) => MapEntry(k.toString(), v == true)),
        );
      } else {
        rematchReadyMap = {};
      }
      myStayResponseSubmitted = rematchReadyMap[myId] == true;
      postGameEndedAt = data['postGameEndedAt'] as int?;

      if (!_isIntentionalLeave && !playerIds.contains(myId)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _isIntentionalLeave) return;
          _sub?.cancel();
          _showGameOver('ルームから退室しました');
        });
      }

      if (postGameActive && isHost && postGameEndedAt == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _db.markPostGameStarted());
      }

      if (rematchHostRequested && awaitingGuestStayResponses) {
        _cancelPostGameTimers();
        _syncGuestStayTimers();
        if (isHost) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _maybeFinalizeRematchLobby());
        }
      } else if (_postGameMessage != null && !rematchHostRequested) {
        _syncPostGameTimers();
      } else if (!awaitingGuestStayResponses) {
        _cancelGuestStayTimers();
      }

      if (rematchHostRequested && !awaitingGuestStayResponses && !gameStarted) {
        _postGameMessage = null;
        _postGameEntered = false;
        _cancelPostGameTimers();
      }

      if (_isActiveGameplay) {
        _postGameMessage = null;
        _postGameEntered = false;
        _cancelPostGameTimers();
        _cancelGuestStayTimers();
      }
    });

    if (data['roomDismissedByHost'] == true && !isHost && !_isClosedDialogShown) {
      _isClosedDialogShown = true;
      _forceReturnToLobby();
      return;
    }

    if (shouldNotifyDeckReset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showGameMessage('山札が尽きたのでシャッフルして補充しました');
      });
    }

    _syncAutoPlayTimer();
    _syncInitialPhaseAutoFlipTimer();
    if (isHost) {
      _syncAllBotTimers();
    }
  }

  bool _shouldStartInitialPhaseAutoFlip() {
    if (!isHost || !mounted || _postGameClosing || _showPostGameOverlay) return false;
    return GameRules.shouldStartInitialPhaseAutoFlip(
      isInitialPhase: isInitialPhase,
      fieldNumber: fieldNumber,
      moriPhase: moriPhase,
      gameStarted: gameStarted,
    );
  }

  String _initialPhaseAutoFlipContextKey() =>
      '$fieldNumber|${fieldSuit.name}|${fieldHistory.length}|$lastPlayerId';

  void _cancelInitialPhaseAutoFlipTimer() {
    _initialPhaseAutoFlipTimer?.cancel();
    _initialPhaseAutoFlipTimer = null;
    _initialPhaseAutoFlipKey = '';
  }

  void _syncInitialPhaseAutoFlipTimer() {
    if (!_shouldStartInitialPhaseAutoFlip()) {
      _cancelInitialPhaseAutoFlipTimer();
      return;
    }

    final key = _initialPhaseAutoFlipContextKey();
    if (key == _initialPhaseAutoFlipKey && _initialPhaseAutoFlipTimer != null) return;

    _initialPhaseAutoFlipKey = key;
    _initialPhaseAutoFlipTimer?.cancel();
    _initialPhaseAutoFlipTimer = Timer(
      Duration(milliseconds: RoomConfig.initialPhaseAutoFlipMs),
      _performInitialPhaseAutoFlip,
    );
  }

  void _performInitialPhaseAutoFlip() {
    _initialPhaseAutoFlipTimer = null;
    _initialPhaseAutoFlipKey = '';
    if (!_shouldStartInitialPhaseAutoFlip()) return;
    _onFlip();
  }

  bool _shouldAutoPlayOnTimeout() {
    if (!mounted || _postGameClosing || _showPostGameOverlay) return false;
    return GameRules.shouldAutoPlayOnTimeout(
      gameStarted: gameStarted,
      isInitialPhase: isInitialPhase,
      fieldNumber: fieldNumber,
      moriPhase: moriPhase,
      currentTurnIndex: currentTurn,
      players: playerIds,
      myId: myId,
      handCount: myHand.length,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
    );
  }

  String _autoPlayContextKey() =>
      '$currentTurn|$lastDrawerId|$isDrawCompetitive|$fieldNumber|${fieldSuit.name}|'
      '$isInitialPhase|$_hasPlayedThisTurn|${myHand.length}|$moriPhase|${myHand.map((c) => '${c.number}${c.suit.name}').join()}';

  void _cancelAutoPlayTimer() {
    _autoPlayTimer?.cancel();
    _autoPlayTimer = null;
    _autoPlayCountdownTimer?.cancel();
    _autoPlayCountdownTimer = null;
    _autoPlayTimerKey = '';
    _autoPlayDeadlineMs = null;
    if (_autoPlayCountdownSeconds != null && mounted) {
      setState(() => _autoPlayCountdownSeconds = null);
    } else {
      _autoPlayCountdownSeconds = null;
    }
  }

  void _updateAutoPlayCountdown() {
    if (!_shouldAutoPlayOnTimeout() || _autoPlayDeadlineMs == null) {
      _cancelAutoPlayTimer();
      return;
    }
    final remaining =
        ((_autoPlayDeadlineMs! - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    final clamped = remaining < 0 ? 0 : remaining;
    if (clamped != _autoPlayCountdownSeconds && mounted) {
      setState(() => _autoPlayCountdownSeconds = clamped);
    }
  }

  void _syncAutoPlayTimer() {
    if (!_shouldAutoPlayOnTimeout()) {
      _cancelAutoPlayTimer();
      return;
    }

    final key = _autoPlayContextKey();
    if (key == _autoPlayTimerKey && _autoPlayTimer != null) return;

    _autoPlayTimerKey = key;
    _autoPlayTimer?.cancel();
    _autoPlayCountdownTimer?.cancel();
    _autoPlayDeadlineMs = DateTime.now().millisecondsSinceEpoch + RoomConfig.autoPlayTimeoutMs;
    _autoPlayCountdownSeconds = RoomConfig.autoPlayTimeoutSeconds;
    _autoPlayTimer = Timer(Duration(milliseconds: RoomConfig.autoPlayTimeoutMs), _performAutoPlay);
    _autoPlayCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateAutoPlayCountdown();
    });
    if (mounted) {
      setState(() => _autoPlayCountdownSeconds = RoomConfig.autoPlayTimeoutSeconds);
    }
  }

  void _performAutoPlay() {
    _autoPlayTimer = null;
    _autoPlayTimerKey = '';
    _autoPlayDeadlineMs = null;
    _autoPlayCountdownTimer?.cancel();
    _autoPlayCountdownTimer = null;
    if (mounted) setState(() => _autoPlayCountdownSeconds = null);

    if (!_shouldAutoPlayOnTimeout()) return;

    final index = GameRules.findPlayableCardIndex(
      fieldNumber: fieldNumber,
      fieldSuit: fieldSuit,
      hand: myHand,
      isInitialPhase: isInitialPhase,
      currentTurnIndex: currentTurn,
      players: playerIds,
      myId: myId,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      hasPlayedThisTurn: _hasPlayedThisTurn,
    );

    if (index != null) {
      _onCardTap(index);
      return;
    }

    if (GameRules.canDraw(myHand.length, lastDrawerId, myId)) {
      _onDraw();
      return;
    }

    if (GameRules.mustPlayAfterSeventhDraw(
      handCount: myHand.length,
      lastDrawerId: lastDrawerId,
      myId: myId,
      currentTurnIndex: currentTurn,
      players: playerIds,
    )) {
      _triggerBurst();
    }
  }

  void _triggerBurst() {
    final myIdx = playerIds.indexOf(myId);
    _db.updateGameStatus({
      'burstPlayerId': myId,
      'currentTurnIndex': myIdx,
      'lastDrawerId': null,
      'isDrawCompetitive': false,
    });
  }

  void _cancelAllBotTimers() {
    for (final timer in _botTimers.values) {
      timer.cancel();
    }
    _botTimers.clear();
    _botTimerKeys.clear();
  }

  void _cancelBotTimer(String botId) {
    _botTimers[botId]?.cancel();
    _botTimers.remove(botId);
    _botTimerKeys.remove(botId);
  }

  bool _shouldRunBotLogic() =>
      isHost && mounted && !_postGameClosing && !_showPostGameOverlay && gameStarted;

  List<CardWidget> _botHand(String botId) =>
      List<CardWidget>.from(_allPlayerCards[botId] ?? []);

  void _syncAllBotTimers() {
    if (!_shouldRunBotLogic()) {
      _cancelAllBotTimers();
      return;
    }

    final activeBotIds = <String>[];
    for (final botId in playerIds.where(BotLogic.isBot)) {
      final hand = _botHand(botId);
      if (BotLogic.shouldBotAct(
        gameStarted: gameStarted,
        isInitialPhase: isInitialPhase,
        fieldNumber: fieldNumber,
        moriPhase: moriPhase,
        currentTurnIndex: currentTurn,
        players: playerIds,
        botId: botId,
        hand: hand,
        lastDrawerId: lastDrawerId,
        isDrawCompetitive: isDrawCompetitive,
        hasPlayedThisTurn: _botHasPlayedThisTurn[botId] ?? false,
        fieldSuit: fieldSuit,
        lastPlayerId: lastPlayerId,
      )) {
        activeBotIds.add(botId);
      }
    }

    for (final botId in _botTimers.keys.toList()) {
      if (!activeBotIds.contains(botId)) _cancelBotTimer(botId);
    }

    for (final botId in activeBotIds) {
      _syncBotTimer(botId);
    }
  }

  void _syncBotTimer(String botId) {
    final hand = _botHand(botId);
    final key = BotLogic.actionContextKey(
      botId: botId,
      currentTurnIndex: currentTurn,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      fieldNumber: fieldNumber,
      fieldSuit: fieldSuit,
      isInitialPhase: isInitialPhase,
      hasPlayedThisTurn: _botHasPlayedThisTurn[botId] ?? false,
      handLength: hand.length,
      moriPhase: moriPhase,
      handSignature: hand.map((c) => '${c.number}${c.suit.name}').join(),
      lastPlayerId: lastPlayerId,
    );
    if (_botTimerKeys[botId] == key && _botTimers[botId] != null) return;

    _cancelBotTimer(botId);
    _botTimerKeys[botId] = key;
    _botTimers[botId] = Timer(
      Duration(milliseconds: RoomConfig.botActionTimeoutMs),
      () => _performBotAction(botId),
    );
  }

  void _performBotAction(String botId) {
    _cancelBotTimer(botId);
    if (!_shouldRunBotLogic() || !BotLogic.isBot(botId)) return;

    final hand = _botHand(botId);
    final decision = BotLogic.decideAction(
      gameStarted: gameStarted,
      isInitialPhase: isInitialPhase,
      fieldNumber: fieldNumber,
      fieldSuit: fieldSuit,
      moriPhase: moriPhase,
      currentTurnIndex: currentTurn,
      players: playerIds,
      botId: botId,
      hand: hand,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      hasPlayedThisTurn: _botHasPlayedThisTurn[botId] ?? false,
      lastPlayerId: lastPlayerId,
    );

    switch (decision.type) {
      case BotActionType.mori:
        _executeBotMori(botId);
      case BotActionType.play:
        if (decision.cardIndex != null) _executeBotPlay(botId, decision.cardIndex!);
      case BotActionType.draw:
        _executeBotDraw(botId);
      case BotActionType.burst:
        _executeBotBurst(botId);
      case BotActionType.none:
        break;
    }
  }

  Future<void> _addBot() async {
    if (!isHost || gameStarted || _postGameClosing) return;
    if (RoomConfig.isRoomFull(playerIds.length, maxPlayers)) {
      _showGameMessage('定員に達しているためBotを追加できません');
      return;
    }

    final botId = '${BotLogic.idPrefix}${DateTime.now().millisecondsSinceEpoch}';
    final botName = BotLogic.nextBotName(playerIds);
    final deckCopy = List<CardWidget>.from(deck);
    final botHand = <CardWidget>[];
    for (var i = 0; i < 5; i++) {
      if (deckCopy.isNotEmpty) botHand.add(deckCopy.removeLast());
    }

    final updatedPlayers = List<String>.from(playerIds)..add(botId);
    await _db.updateGameStatus({
      'players': updatedPlayers,
      'playerHands/$botId': botHand.length,
      'playerCards/$botId': _serializeHand(botHand),
      'playerNames/$botId': botName,
      'bots/$botId': true,
      'deck': deckCopy.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'deckIndex': deckCopy.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
    });
    _showGameMessage('$botName を追加しました');
  }

  void _executeBotPlay(String botId, int index) {
    if (isInitialPhase) _cancelInitialPhaseAutoFlipTimer();
    final hand = _botHand(botId);
    if (index < 0 || index >= hand.length) return;

    final card = hand[index];
    if (isInitialPhase) {
      if (!GameRules.canPlayNormal(fieldNumber, fieldSuit, card, isInitialPhase: true)) return;
    } else {
      final botIdx = playerIds.indexOf(botId);
      final isServerTurn = currentTurn % playerIds.length == botIdx;
      final isLastDrawer = lastDrawerId == botId;
      final isCompetitiveParticipant = GameRules.canPlayInDrawCompetition(
        isDrawCompetitive: isDrawCompetitive,
        lastDrawerId: lastDrawerId,
        players: playerIds,
        myId: botId,
      );
      final isInterrupt = card.number == fieldNumber;
      final isJokerField = GameRules.isJokerOnField(fieldNumber, fieldSuit);
      final usesTurnPlayLimit = isServerTurn || isLastDrawer || isCompetitiveParticipant;
      final hasPlayed = _botHasPlayedThisTurn[botId] ?? false;
      if (usesTurnPlayLimit && hasPlayed && !isInterrupt && !isJokerField) return;
      if (!(isServerTurn ||
          isLastDrawer ||
          isCompetitiveParticipant ||
          isInterrupt ||
          isJokerField)) {
        return;
      }
      if (!(GameRules.canPlayNormal(fieldNumber, fieldSuit, card) || isInterrupt || isJokerField)) {
        return;
      }
    }

    hand.removeAt(index);
    _allPlayerCards[botId] = hand;
    _botHasPlayedThisTurn[botId] = true;

    final botIdx = playerIds.indexOf(botId);
    final updatedHistory = List<CardWidget>.from(fieldHistory)..add(card);
    fieldHistory = updatedHistory;

    _db.updateGameStatus({
      'field': {'number': card.number, 'suit': card.suit.name},
      'playerHands/$botId': hand.length,
      'playerCards/$botId': _serializeHand(hand),
      'lastPlayerId': botId,
      'currentTurnIndex': (botIdx + 1) % playerIds.length,
      'lastDrawerId': null,
      'isDrawCompetitive': false,
      'isInitialPhase': false,
      'gameStarted': true,
      'fieldHistory': updatedHistory.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
    });
  }

  void _executeBotDraw(String botId) {
    if (moriPhase != 'none' || isInitialPhase) return;
    final hand = _botHand(botId);
    final botIdx = playerIds.indexOf(botId);
    final isScheduledTurn = currentTurn % playerIds.length == botIdx;
    final canDrawInCompetition = GameRules.canDrawInCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: playerIds,
      myId: botId,
      handCount: hand.length,
    );
    if (!isScheduledTurn && !canDrawInCompetition) return;
    if (!GameRules.canDraw(hand.length, lastDrawerId, botId)) return;

    if (deck.isEmpty) {
      _replenishDeckFromFieldIfEmpty();
      if (deck.isEmpty) return;
    }

    final drawn = deck.last;
    final tempHand = List<CardWidget>.from(hand)..add(drawn);
    final hasPlayableCard = tempHand.any((c) => GameRules.canPlayNormal(fieldNumber, fieldSuit, c));

    var deckAfterDrawCards = deck.sublist(0, deck.length - 1);
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
    final isSeventhDraw = tempHand.length >= 7;

    if (GameRules.isBurst(tempHand.length, hasPlayableCard)) {
      _allPlayerCards[botId] = tempHand;
      _db.updateGameStatus({
        'burstPlayerId': botId,
        'deck': deckAfterDraw,
        'deckIndex': deckAfterDraw,
        'playerHands/$botId': tempHand.length,
        'playerCards/$botId': _serializeHand(tempHand),
        'currentTurnIndex': botIdx,
        'lastDrawerId': null,
        'isDrawCompetitive': false,
        ...resetMetaUpdates,
      });
      return;
    }

    _allPlayerCards[botId] = tempHand;
    _db.updateGameStatus({
      'deck': deckAfterDraw,
      'deckIndex': deckAfterDraw,
      'playerHands/$botId': tempHand.length,
      'playerCards/$botId': _serializeHand(tempHand),
      if (isSeventhDraw) ...{
        'currentTurnIndex': botIdx,
        'lastDrawerId': botId,
        'isDrawCompetitive': false,
      } else ...{
        'currentTurnIndex': (botIdx + 1) % playerIds.length,
        'lastDrawerId': botId,
        'isDrawCompetitive': true,
      },
      ...resetMetaUpdates,
    });
  }

  void _executeBotMori(String botId) {
    final hand = _botHand(botId);
    if (!BotLogic.canDeclareMori(
      fieldNumber: fieldNumber,
      hand: hand,
      moriPhase: moriPhase,
      lastPlayerId: lastPlayerId,
      playerId: botId,
    )) {
      return;
    }

    _db.updateGameStatus({
      'moriPhase': 'mori_declared',
      'lastMoriPlayerId': botId,
      'loserPlayerId': lastPlayerId,
      'moriRevealedHand': _serializeHand(hand),
      'moriRevealedType': 'mori',
    });
  }

  void _executeBotBurst(String botId) {
    final botIdx = playerIds.indexOf(botId);
    _db.updateGameStatus({
      'burstPlayerId': botId,
      'currentTurnIndex': botIdx,
      'lastDrawerId': null,
      'isDrawCompetitive': false,
    });
  }

  void _onCardTap(int index) {
    _cancelAutoPlayTimer();
    if (isInitialPhase) _cancelInitialPhaseAutoFlipTimer();
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
    _cancelAutoPlayTimer();
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
    if (!GameRules.isValidMori(fieldNumber, myHand)) { _showGameMessage('計算が合いません！'); return; }
    setState(() => hasDeclaredMori = true);
    final revealedHand = _serializeHand(myHand);
    if (moriPhase == 'none') {
      if (lastPlayerId == myId) { _showGameMessage('自滅はできません！'); setState(() => hasDeclaredMori = false); return; }
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
    _cancelInitialPhaseAutoFlipTimer();
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
      'roomStatus': 'closed',
      'gameStarted': true,
      'rematchHostRequested': false,
      'postGameActive': false,
      'burstPlayerId': null,
      'lastMoriPlayerId': null,
      'loserPlayerId': null,
      'moriPhase': 'none',
      'moriRevealedHand': null,
      'moriRevealedType': null,
    });
    setState(() {
      _postGameMessage = null;
      _postGameEntered = false;
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
        _showGameMessage('山札を補充できません（捨て札が不足しています）');
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
      return;
    }

    List<String> p = List<String>.from(playerIds)..remove(myId);
    _db.updateGameStatus({
      'players': p,
      'playerHands/$myId': null,
      'playerCards/$myId': null,
      'playerNames/$myId': null,
    });
  }

  void _closeRoomForcefully({bool dismissedByHost = false}) {
    if (dismissedByHost) {
      _db.dismissRoomByHost();
    } else {
      _db.updateGameStatus({'roomStatus': 'closed'});
    }
    Timer(const Duration(seconds: 2), () => FirebaseDatabase.instance.ref('rooms/${widget.roomId}').remove());
  }

  void _forceReturnToLobby() {
    if (_postGameClosing || _isIntentionalLeave) return;
    _postGameClosing = true;
    _isIntentionalLeave = true;
    _cancelPostGameTimers();
    _cancelGuestStayTimers();
    _sub?.cancel();
    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

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

  void _cancelPostGameTimers() {
    _hostDecisionTimer?.cancel();
    _hostDecisionTimer = null;
    _postGameCountdownTimer?.cancel();
    _postGameCountdownTimer = null;
    _countdownSeconds = null;
  }

  void _cancelGuestStayTimers() {
    _guestStayCountdownTimer?.cancel();
    _guestStayCountdownTimer = null;
    _guestCountdownSeconds = null;
  }

  void _syncGuestStayTimers() {
    _guestStayCountdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateGuestCountdown();
      if (isHost) _maybeFinalizeRematchLobby();
    });
    _updateGuestCountdown();
  }

  void _updateGuestCountdown() {
    if (rematchStartedAt == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next =
        ((rematchStartedAt! + RoomConfig.guestRematchResponseMs - now) / 1000).ceil();
    final clamped = next < 0 ? 0 : next;
    if (clamped != _guestCountdownSeconds) setState(() => _guestCountdownSeconds = clamped);
  }

  int _guestStayReadyCount() =>
      rematchEligiblePlayers.where((id) => rematchReadyMap[id] == true).length;

  bool _allGuestStayResponsesResolved({required bool timedOut}) {
    for (final id in rematchEligiblePlayers) {
      if (!playerIds.contains(id)) continue;
      if (rematchReadyMap[id] != true && !timedOut) return false;
    }
    return true;
  }

  Future<void> _maybeFinalizeRematchLobby() async {
    if (!isHost || !awaitingGuestStayResponses || _rematchFinalizing) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final timedOut = rematchStartedAt != null &&
        now >= rematchStartedAt! + RoomConfig.guestRematchResponseMs;

    if (!_allGuestStayResponsesResolved(timedOut: timedOut)) return;

    _rematchFinalizing = true;
    try {
      final stayingGuests = rematchEligiblePlayers
          .where((id) => !BotLogic.isBot(id) && playerIds.contains(id) && rematchReadyMap[id] == true)
          .toList();
      final toRemove = rematchEligiblePlayers
          .where((id) => !BotLogic.isBot(id) && playerIds.contains(id) && rematchReadyMap[id] != true)
          .toList();

      if (toRemove.isNotEmpty) {
        final updates = <String, dynamic>{};
        final newPlayers = List<String>.from(playerIds);
        for (final id in toRemove) {
          newPlayers.remove(id);
          updates['playerHands/$id'] = null;
          updates['playerCards/$id'] = null;
          updates['playerNames/$id'] = null;
          updates['rematchReady/$id'] = null;
        }
        updates['players'] = newPlayers;
        await _db.updateGameStatus(updates);
        playerIds = newPlayers;
      }

      final remaining = <String>[?hostId, ...stayingGuests];
      if (remaining.length < RoomConfig.minPlayers) {
        await _closeRoomAndExitLobby();
        return;
      }
      await _finalizeRematchWithPlayers(remaining);
    } finally {
      _rematchFinalizing = false;
    }
  }

  Future<void> _finalizeRematchWithPlayers(List<String> players) async {
    _cancelGuestStayTimers();
    final humanPlayers = players.where((p) => !BotLogic.isBot(p)).toList();
    final deckCards = _generateDeck()..shuffle();
    final playerCards = <String, List<Map<String, dynamic>>>{};
    final playerHandCounts = <String, int>{};

    for (final pid in humanPlayers) {
      final hand = <CardWidget>[];
      for (int i = 0; i < 5; i++) {
        if (deckCards.isNotEmpty) hand.add(deckCards.removeLast());
      }
      playerCards[pid] = hand.map((c) => {'number': c.number, 'suit': c.suit.name}).toList();
      playerHandCounts[pid] = hand.length;
    }
    final remainingDeck =
        deckCards.map((c) => {'number': c.number, 'suit': c.suit.name}).toList();

    await _db.prepareRematchLobby(
      players: humanPlayers,
      playerCards: playerCards,
      playerHands: playerHandCounts,
      deck: remainingDeck,
    );

    if (!mounted) return;
    setState(() {
      _postGameMessage = null;
      _postGameEntered = false;
      awaitingGuestStayResponses = false;
      rematchEligiblePlayers = [];
      rematchReadyMap = {};
      myStayResponseSubmitted = false;
      postGameActive = false;
      gameStarted = false;
      roomStatus = 'open';
      isInitialPhase = true;
      fieldNumber = -1;
      fieldSuit = Suit.joker;
      fieldHistory = [];
      myHand = (playerCards[myId] ?? [])
          .map((i) => CardWidget(
                number: i['number'] as int,
                suit: Suit.values.firstWhere((e) => e.name == i['suit']),
              ))
          .toList();
      _hasPlayedThisTurn = false;
      hasDeclaredMori = false;
    });
    _showGameMessage('ルームを公開しました。参加者が揃ったら山札をめくってください。');
  }

  void _syncPostGameTimers() {
    _postGameCountdownTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateCountdown();
      _checkPostGameTimeouts();
    });
    _updateCountdown();
  }

  void _updateCountdown() {
    if (postGameEndedAt == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final next = ((postGameEndedAt! + RoomConfig.hostRematchDecisionMs - now) / 1000).ceil();
    final clamped = next < 0 ? 0 : next;
    if (clamped != _countdownSeconds) setState(() => _countdownSeconds = clamped);
  }

  void _checkPostGameTimeouts() {
    if (!isHost || rematchHostRequested || postGameEndedAt == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now >= postGameEndedAt! + RoomConfig.hostRematchDecisionMs) {
      _closeRoomAndExitLobby();
    }
  }

  Future<void> _removeAllBotsFromRoom() async {
    final botIds = playerIds.where(BotLogic.isBot).toList();
    if (botIds.isEmpty) return;

    final updates = <String, dynamic>{};
    final newPlayers = List<String>.from(playerIds);
    for (final id in botIds) {
      newPlayers.remove(id);
      updates['playerHands/$id'] = null;
      updates['playerCards/$id'] = null;
      updates['playerNames/$id'] = null;
      updates['bots/$id'] = null;
      updates['rematchReady/$id'] = null;
    }
    updates['players'] = newPlayers;
    await _db.updateGameStatus(updates);

    for (final id in botIds) {
      _allPlayerCards.remove(id);
      _botHasPlayedThisTurn.remove(id);
      _cancelBotTimer(id);
    }
    playerIds = newPlayers;
  }

  Future<void> _onHostRematchRequest() async {
    _cancelPostGameTimers();
    await _removeAllBotsFromRoom();
    if (!mounted) return;

    final guests = playerIds.where((p) => p != hostId && !BotLogic.isBot(p)).toList();
    if (guests.isEmpty) {
      await _finalizeRematchWithPlayers([hostId!]);
      if (mounted) setState(() => _postGameMessage = null);
      return;
    }

    await _db.requestHostRematch(guests);
    if (!mounted) return;
    setState(() {
      rematchHostRequested = true;
      awaitingGuestStayResponses = true;
      rematchEligiblePlayers = guests;
      postGameActive = false;
    });
  }

  Future<void> _onGuestStayInRoom() async {
    if (isHost || !awaitingGuestStayResponses || myStayResponseSubmitted) return;
    if (!rematchEligiblePlayers.contains(myId)) return;
    await _db.setStayInRoom(myId);
    if (!mounted) return;
    setState(() => myStayResponseSubmitted = true);
  }

  Future<void> _onHostReturnToLobby() async {
    await _closeRoomAndExitLobby();
  }

  Future<void> _leaveRoomToLobby() async {
    if (_postGameClosing) return;
    _postGameClosing = true;
    _isIntentionalLeave = true;
    _cancelPostGameTimers();
    _sub?.cancel();

    List<String> p = List<String>.from(playerIds)..remove(myId);
    final updates = <String, dynamic>{
      'players': p,
      'playerHands/$myId': null,
      'playerCards/$myId': null,
      'playerNames/$myId': null,
      'rematchReady/$myId': null,
    };
    await _db.updateGameStatus(updates);

    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  void _enterPostGame(String message) {
    if (_postGameMessage != null || _postGameEntered) return;
    _postGameEntered = true;
    setState(() => _postGameMessage = message);
    if (isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _db.markPostGameStarted());
    }
  }

  Future<void> _closeRoomAndExitLobby() async {
    if (_postGameClosing) return;
    _postGameClosing = true;
    _isIntentionalLeave = true;
    _cancelPostGameTimers();
    _sub?.cancel();
    _closeRoomForcefully(dismissedByHost: true);
    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  void _showGameOver(String msg) {
    if (_gameOverDialogShown) return;
    _gameOverDialogShown = true;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(msg),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _gameOverDialogShown = false;
              Navigator.popUntil(context, (r) => r.isFirst);
            },
            child: const Text('ロビーへ'),
          ),
        ],
      ),
    ).then((_) => _gameOverDialogShown = false);
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
      playerCount: playerIds.length,
      maxPlayers: maxPlayers, gameStarted: gameStarted,
      statusMessage: _statusMessage,
      autoPlayCountdownSeconds: _autoPlayCountdownSeconds,
      postGameVisible: _showPostGameOverlay,
      postGameMessage: _postGameMessage ?? '',
      postGameCountdownSeconds: _countdownSeconds,
      awaitingGuestStayResponses: awaitingGuestStayResponses,
      guestStayReadyCount: _guestStayReadyCount(),
      guestStayTotalCount: rematchEligiblePlayers.length,
      guestCountdownSeconds: _guestCountdownSeconds,
      mustRespondToStay: !isHost &&
          awaitingGuestStayResponses &&
          rematchEligiblePlayers.contains(myId) &&
          !myStayResponseSubmitted,
      myStayResponseSubmitted: myStayResponseSubmitted,
      onHostRematch: _onHostRematchRequest,
      onHostReturnToLobby: _onHostReturnToLobby,
      onGuestStayInRoom: _onGuestStayInRoom,
      onLeaveToLobby: _leaveRoomToLobby,
      canAddBot: isHost && !gameStarted && !RoomConfig.isRoomFull(playerIds.length, maxPlayers),
      onAddBot: _addBot,
      onCardTap: _onCardTap, onMori: _onMori, onDraw: _onDraw, onFlip: _onFlip,
    );
  }
}