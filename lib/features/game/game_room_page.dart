import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:async';
import 'dart:math';
import '../../effects/game_effects.dart';
import '../../effects/game_effects_overlay.dart';
import '../../services/firebase_db.dart';
import '../../logic/game_rules.dart';
import '../../logic/bot_logic.dart';
import '../../logic/room_config.dart';
import '../../logic/scoring_rules.dart';
import '../../logic/player_display_name.dart';
import '../../logic/match_record_codec.dart';
import '../../logic/post_game_summary_builder.dart';
import '../../models/match_event.dart';
import '../../models/post_game_summary.dart';
import '../../services/game_display_settings.dart';
import '../../services/match_record_service.dart';
import '../../services/rating_service.dart';
import 'game_board_view.dart';

class GameRoomPage extends StatefulWidget {
  final String roomId;
  final bool isPrivate;
  final String playerName;
  final int? maxPlayers;
  final int? totalMatches;
  final int? turnTimeoutSeconds;
  final String? userId;
  final bool isSpectator;
  const GameRoomPage({
    super.key,
    required this.roomId,
    this.isPrivate = false,
    required this.playerName,
    this.maxPlayers,
    this.totalMatches,
    this.turnTimeoutSeconds,
    this.userId,
    this.isSpectator = false,
  });
  @override
  State<GameRoomPage> createState() => _GameRoomPageState();
}

class _GameRoomPageState extends State<GameRoomPage> with WidgetsBindingObserver {
  late final FirebaseDB _db;
  late final RatingService _ratingService;
  final MatchRecordService _matchRecordService = MatchRecordService();
  final GameDisplaySettings _gameDisplaySettings = GameDisplaySettings();
  final GameEffects _gameEffects = GameEffects();
  StreamSubscription? _sub;
  String myId = '';

  List<CardWidget> myHand = [];
  String? hostId;
  List<String> playerIds = [];
  Map<String, String> playerNames = {};
  Map<String, int> playerPoints = {};
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
  String? burstPlayerId;
  int moriGaeshiCount = 0;
  List<int> moriDeclarationFactors = [];
  List<String> moriDeclaredPlayerIds = [];
  Set<String> openJokerPlayerIds = {};
  List<CardWidget> moriRevealedHand = [];
  String? moriRevealedType;
  int? moriDeclaredAt;
  int? _moriResolutionDeadlineMs;
  int? _moriCountdownSeconds;
  Timer? _moriCountdownTimer;
  String _moriResolutionKey = '';
  bool _moriFinishRequested = false;
  PostGameSummary? _postGameSummary;
  Map<String, int> _lastMatchPointDeltas = {};
  Map<String, Map<String, dynamic>> _seriesRatingDetails = {};
  String roomStatus = 'open'; 
  bool _isClosedDialogShown = false;
  bool _gameOverDialogShown = false;
  bool _isIntentionalLeave = false;
  bool _postGameClosing = false;
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
  int totalMatches = RoomConfig.defaultMatchCount;
  int turnTimeoutSeconds = RoomConfig.defaultTurnTimeoutSeconds;
  int completedMatches = 0;
  List<String> seriesPlayerIds = [];
  bool gameStarted = false;
  bool _seriesAutoContinueScheduled = false;
  bool _seriesRestartInProgress = false;
  Timer? _seriesContinueTimer;
  Timer? _seriesUiCountdownTimer;

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
  final Random _botRandom = Random();
  bool _hideOpponentNames = false;
  Map<String, String> spectatorNames = {};
  Map<String, List<CardWidget>> _spectatorPlayerCards = {};
  bool _hostDisconnectHandlerRegistered = false;
  String? _lastEffectEventKey;

  bool get isSpectator => widget.isSpectator;

  bool get isHost => !isSpectator && myId == hostId;

  int get _turnTimeoutMs => turnTimeoutSeconds * 1000;

  bool get _isActiveGameplay =>
      gameStarted && !postGameActive && !awaitingGuestStayResponses;

  bool get _showPostGameOverlay => _postGameEntered;

  bool get _hasRemainingSeriesMatches =>
      totalMatches > 1 && completedMatches < totalMatches;

  int get _currentMatchNumber => completedMatches + 1;

  String get _matchProgressLabel =>
      totalMatches > 1 ? '第$_currentMatchNumber戦 / 全$totalMatches戦' : '';

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
    _ratingService = RatingService();
    myId = widget.userId ?? DateTime.now().millisecondsSinceEpoch.toString();
    _loadDisplaySettings();
    _init();
  }

  Future<void> _loadDisplaySettings() async {
    final hide = await _gameDisplaySettings.getHideOpponentNames();
    if (!mounted) return;
    setState(() => _hideOpponentNames = hide);
  }

  Future<void> _toggleHideOpponentNames() async {
    final next = !_hideOpponentNames;
    setState(() => _hideOpponentNames = next);
    if (_postGameEntered) _syncPostGameSummary();
    await _gameDisplaySettings.setHideOpponentNames(next);
  }

  @override
  void dispose() {
    if (isSpectator) {
      if (!_isIntentionalLeave) _db.leaveAsSpectator(myId);
    } else if (!_isIntentionalLeave) {
      _cleanupRoomOnLeave();
    }
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _moriCountdownTimer?.cancel();
    _statusMessageTimer?.cancel();
    _hostDecisionTimer?.cancel();
    _postGameCountdownTimer?.cancel();
    _cancelGuestStayTimers();
    _cancelAutoPlayTimer();
    _cancelInitialPhaseAutoFlipTimer();
    _cancelAllBotTimers();
    _seriesContinueTimer?.cancel();
    _seriesUiCountdownTimer?.cancel();
    _gameEffects.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (isSpectator) return;
    if (!isHost) return;
    if (gameStarted) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _closeRoomForcefully();
    }
  }

  DatabaseReference get _roomRef => FirebaseDatabase.instance.ref('rooms/${widget.roomId}');

  void _registerHostDisconnectClose() {
    if (!isHost || _hostDisconnectHandlerRegistered) return;
    _hostDisconnectHandlerRegistered = true;
    _roomRef.onDisconnect().update({'roomStatus': 'closed'});
  }

  Future<void> _cancelHostDisconnectClose() async {
    if (!_hostDisconnectHandlerRegistered) return;
    _hostDisconnectHandlerRegistered = false;
    try {
      await _roomRef.onDisconnect().cancel();
    } catch (_) {
      // 未接続など
    }
  }

  Future<void> _initSpectator() async {
    final snap = await _db.getSnapshot();
    if (!snap.exists) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showErrorDialog('ルームが見つかりません。'),
      );
      return;
    }

    final isStarted = snap.child('gameStarted').value == true;
    if (!isStarted) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showErrorDialog('観戦できるのは進行中のゲームのみです。'),
      );
      return;
    }

    final players = List<String>.from(snap.child('players').value as List? ?? []);
    if (players.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showErrorDialog('プレイヤーがいないため観戦できません。'),
      );
      return;
    }

    await _db.joinAsSpectator(myId, widget.playerName);
    FirebaseDatabase.instance
        .ref('rooms/${widget.roomId}/spectators/$myId')
        .onDisconnect()
        .remove();

    _sub = _db.roomStream.listen(_onData);
  }

  Future<void> _init() async {
    if (isSpectator) {
      await _initSpectator();
      return;
    }
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
        totalMatches: widget.totalMatches ?? RoomConfig.defaultMatchCount,
        turnTimeoutSeconds:
            widget.turnTimeoutSeconds ?? RoomConfig.defaultTurnTimeoutSeconds,
        deckIndex: _serializeHand(fullDeck),
        initialHand: _serializeHand(hand),
      );
      maxPlayers = widget.maxPlayers ?? RoomConfig.defaultMaxPlayers;
      totalMatches = widget.totalMatches ?? RoomConfig.defaultMatchCount;
      turnTimeoutSeconds =
          widget.turnTimeoutSeconds ?? RoomConfig.defaultTurnTimeoutSeconds;
      _registerHostDisconnectClose();
      await _db.registerPlayerPresence(myId);
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
        'playerPoints/$myId': 0,
        'deck': cDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
        'deckIndex': cDeck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      });
      await _db.registerPlayerPresence(myId);
      setState(() => myHand = iHand);
    }
    if (isHost && !gameStarted) {
      _registerHostDisconnectClose();
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
    final prevFieldNumber = fieldNumber;
    final prevFieldSuit = fieldSuit;
    final prevLastPlayerId = lastPlayerId;
    final prevLastDrawerId = lastDrawerId;
    final prevMoriPhase = moriPhase;
    final prevMoriGaeshiCount = moriGaeshiCount;
    final bool dataPostGameActive = data['postGameActive'] == true;
    final bool dataSeriesRestarting = data['seriesRestarting'] == true;
    final int? seriesNextMatchAt = _parseFirebaseTimestamp(data['seriesNextMatchAt']);
    final bool shouldNotifyDeckReset =
        deckResetAt != null && deckResetAt != _lastDeckResetAt;
    setState(() {
      hostId = data['host'];
      playerIds = List<String>.from(data['players'] ?? []);
      maxPlayers = RoomConfig.resolveMaxPlayers(data['maxPlayers']);
      totalMatches = RoomConfig.resolveMatchCount(data['totalMatches']);
      turnTimeoutSeconds = RoomConfig.resolveTurnTimeoutSeconds(data['turnTimeoutSeconds']);
      completedMatches = RoomConfig.resolveNonNegativeInt(data['completedMatches']);
      if (data['seriesPlayerIds'] is List) {
        seriesPlayerIds = List<String>.from(
          (data['seriesPlayerIds'] as List).map((e) => e.toString()),
        );
      } else {
        seriesPlayerIds = [];
      }
      gameStarted = data['gameStarted'] == true;
      if (isHost && gameStarted && _hostDisconnectHandlerRegistered) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _cancelHostDisconnectClose());
      }
      if (data['playerNames'] != null) {
        playerNames = Map<String, String>.from(
          (data['playerNames'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      }
      if (data['spectators'] is Map) {
        spectatorNames = Map<String, String>.from(
          (data['spectators'] as Map).map((k, v) => MapEntry(k.toString(), v.toString())),
        );
      } else {
        spectatorNames = {};
      }
      if (data['playerPoints'] != null) {
        playerPoints = Map<String, int>.from(
          (data['playerPoints'] as Map).map(
            (k, v) => MapEntry(k.toString(), v is int ? v : (v as num).round()),
          ),
        );
      }
      currentTurn = data['currentTurnIndex'] ?? 0;
      lastPlayerId = data['lastPlayerId'];
      roomStatus = data['roomStatus'] ?? 'open';
      
      lastDrawerId = data['lastDrawerId'];
      isDrawCompetitive = data['isDrawCompetitive'] == true;
      if (shouldNotifyDeckReset) _lastDeckResetAt = deckResetAt;

      if (!isSpectator) {
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
        if (isSpectator) _spectatorPlayerCards = parsedAll;
        handCounts = {...handCounts, ...countsFromCards};
        if (!isSpectator && playerCards[myId] is List) {
          myHand = parsedAll[myId] ?? _parseHandFromFirebase(playerCards[myId]);
        }
      }

      if (!isSpectator && isHost) {
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
      moriDeclaredAt = _parseFirebaseTimestamp(data['moriDeclaredAt']);
      moriRevealedHand = _parseHandFromFirebase(data['moriRevealedHand']);
      moriRevealedType = data['moriRevealedType'] as String?;
      moriGaeshiCount = data['moriGaeshiCount'] as int? ?? 0;
      if (data['moriDeclaredPlayerIds'] is List) {
        moriDeclaredPlayerIds = (data['moriDeclaredPlayerIds'] as List)
            .map((e) => e.toString())
            .toList();
      } else if (moriPhase == 'none') {
        moriDeclaredPlayerIds = [];
      }
      if (data['openJokerPlayerIds'] is Map) {
        openJokerPlayerIds = (data['openJokerPlayerIds'] as Map)
            .entries
            .where((e) => e.value == true)
            .map((e) => e.key.toString())
            .toSet();
      } else {
        openJokerPlayerIds = {};
      }
      if (data['moriDeclarationFactors'] is List) {
        moriDeclarationFactors = (data['moriDeclarationFactors'] as List)
            .map((e) => e is int ? e : (e as num).round())
            .toList();
      } else if (moriPhase == 'none') {
        moriDeclarationFactors = [];
      }
      burstPlayerId = data['burstPlayerId'] as String?;
      if (moriPhase == 'none') {
        moriRevealedHand = [];
        moriRevealedType = null;
        moriDeclaredAt = null;
        _moriFinishRequested = false;
        moriGaeshiCount = 0;
        moriDeclarationFactors = [];
        moriDeclaredPlayerIds = [];
      }
      
      // 山札めくりやゲーム終了後の閉鎖では弾かない（ホスト切断時のロビー閉鎖のみ）
      if (roomStatus == 'closed' &&
          !gameStarted &&
          !dataPostGameActive &&
          !isHost &&
          !_isClosedDialogShown &&
          !_shouldSkipClosedRoomKick(
            dataPostGameActive: dataPostGameActive,
            dataSeriesRestarting: dataSeriesRestarting,
            seriesNextMatchAt: seriesNextMatchAt,
            seriesPlayerIdsRaw: data['seriesPlayerIds'],
          )) {
        _isClosedDialogShown = true;
        _sub?.cancel();
        _showGameOver("ホスト不在のため閉鎖されました");
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

      if (!_isIntentionalLeave &&
          !isSpectator &&
          !playerIds.contains(myId) &&
          !dataSeriesRestarting &&
          seriesNextMatchAt == null &&
          !_isInFixedSeriesRoster(data['seriesPlayerIds'], myId)) {
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
      } else if (_postGameEntered && !rematchHostRequested) {
        if (!_hasRemainingSeriesMatches) {
          _syncPostGameTimers();
        }
      } else if (!awaitingGuestStayResponses) {
        _cancelGuestStayTimers();
      }

      if (rematchHostRequested && !awaitingGuestStayResponses && !gameStarted) {
        _postGameSummary = null;
        _postGameEntered = false;
        _lastMatchPointDeltas = {};
        _seriesRatingDetails = {};
        _cancelPostGameTimers();
      }

      if (_isActiveGameplay &&
          moriPhase != 'finished' &&
          moriPhase != 'mori_declared' &&
          burstPlayerId == null) {
        _postGameSummary = null;
        _postGameEntered = false;
        _lastMatchPointDeltas = {};
        _seriesRatingDetails = {};
        _cancelPostGameTimers();
        _cancelGuestStayTimers();
      }
    });

    if (!_postGameEntered && moriPhase == 'finished' && lastMoriPlayerId != null) {
      _cancelMoriResolutionTimers();
      _enterPostGame();
    }

    final burstId = data['burstPlayerId'] as String?;
    if (!_postGameEntered && burstId != null) {
      _enterPostGame();
    }

    if (data['lastMatchPointDeltas'] is Map) {
      _lastMatchPointDeltas = Map<String, int>.from(
        (data['lastMatchPointDeltas'] as Map).map(
          (k, v) => MapEntry(k.toString(), v is int ? v : (v as num).round()),
        ),
      );
    }
    if (data['seriesRatingDetails'] is Map) {
      _seriesRatingDetails = (data['seriesRatingDetails'] as Map).map(
        (k, v) => MapEntry(
          k.toString(),
          v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{},
        ),
      );
    }
    if (_postGameEntered) {
      _syncPostGameSummary();
    }

    if (data['roomDismissedByHost'] == true && !isHost && !_isClosedDialogShown) {
      _isClosedDialogShown = true;
      _forceReturnToLobby();
      return;
    }

    _syncMoriResolution();

    if (_postGameEntered && _hasRemainingSeriesMatches && seriesNextMatchAt != null) {
      _syncSeriesContinueUi(seriesNextMatchAt);
    } else if (_postGameEntered && totalMatches > 1 && completedMatches >= totalMatches) {
      _syncPostGameSummary();
    }

    if (isHost) {
      _maybeTriggerSeriesRestart(
        seriesNextMatchAt: seriesNextMatchAt,
        dataSeriesRestarting: dataSeriesRestarting,
      );
    }

    if (shouldNotifyDeckReset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showGameMessage('山札が尽きたのでシャッフルして補充しました');
      });
    }

    if (!isSpectator) {
      _syncAutoPlayTimer();
      _syncInitialPhaseAutoFlipTimer();
      if (isHost) {
        _syncAllBotTimers();
      }
    }

    _syncSyncedGameEffects(
      prevFieldNumber: prevFieldNumber,
      prevFieldSuit: prevFieldSuit,
      prevLastPlayerId: prevLastPlayerId,
      prevLastDrawerId: prevLastDrawerId,
      prevMoriPhase: prevMoriPhase,
      prevMoriGaeshiCount: prevMoriGaeshiCount,
    );
  }

  void _onUiButtonPress(VoidCallback action) {
    _gameEffects.playButton();
    action();
  }

  void _emitCardPlayEffect({
    required String actorId,
    required int previousFieldNumber,
    required int newFieldNumber,
  }) {
    if (!gameStarted || newFieldNumber == -1) return;
    final key = 'play|$actorId|$previousFieldNumber|$newFieldNumber';
    if (_lastEffectEventKey == key) return;
    _lastEffectEventKey = key;
    _gameEffects.playCard();
  }

  void _emitDrawEffect({required String actorId}) {
    if (!gameStarted) return;
    final key = 'draw|$actorId|${lastDrawerId ?? ''}';
    if (_lastEffectEventKey == key) return;
    _lastEffectEventKey = key;
    _gameEffects.playCard();
  }

  void _emitMoriEffect({
    required String actorId,
    required bool isGaeshi,
    required List<CardWidget> hand,
  }) {
    final handKey = hand.map((c) => '${c.number}${c.suit.name}').join(',');
    final key = 'mori|$actorId|${isGaeshi ? 'gaeshi' : 'mori'}|$handKey';
    if (_lastEffectEventKey == key) return;
    _lastEffectEventKey = key;

    if (isGaeshi) {
      _gameEffects.playMorigaeshi();
    } else {
      _gameEffects.playMoriDeclaration(hand: hand);
    }
  }

  void _syncSyncedGameEffects({
    required int prevFieldNumber,
    required Suit prevFieldSuit,
    required String? prevLastPlayerId,
    required String? prevLastDrawerId,
    required String prevMoriPhase,
    required int prevMoriGaeshiCount,
  }) {
    if (!gameStarted) return;

    final actor = lastPlayerId;
    final fieldChanged =
        fieldNumber != prevFieldNumber || fieldSuit != prevFieldSuit;
    final skipPlay = !isInitialPhase &&
        prevFieldNumber != -1 &&
        fieldNumber == prevFieldNumber &&
        actor != null &&
        actor != prevLastPlayerId;
    if (actor != null &&
        actor != 'system' &&
        (fieldChanged || skipPlay)) {
      _emitCardPlayEffect(
        actorId: actor,
        previousFieldNumber: prevFieldNumber,
        newFieldNumber: fieldNumber,
      );
    }

    final drawer = lastDrawerId;
    if (drawer != null &&
        drawer != prevLastDrawerId &&
        fieldNumber == prevFieldNumber &&
        fieldSuit == prevFieldSuit) {
      _emitDrawEffect(actorId: drawer);
    }

    if (prevMoriPhase == 'none' && moriPhase == 'mori_declared') {
      final actorId = lastMoriPlayerId;
      if (actorId != null) {
        _emitMoriEffect(
          actorId: actorId,
          isGaeshi: false,
          hand: moriRevealedHand,
        );
      }
    } else if (moriGaeshiCount > prevMoriGaeshiCount) {
      final actorId = lastMoriPlayerId;
      if (actorId != null) {
        _emitMoriEffect(
          actorId: actorId,
          isGaeshi: true,
          hand: moriRevealedHand,
        );
      }
    }
  }

  bool _isInFixedSeriesRoster(dynamic raw, String playerId) {
    if (raw is! List || raw.isEmpty) return false;
    return raw.any((id) => id.toString() == playerId);
  }

  List<String> _readSeriesRosterFromSnapshot(DataSnapshot snap) {
    final seriesRaw = snap.child('seriesPlayerIds').value;
    if (seriesRaw is List && seriesRaw.isNotEmpty) {
      return seriesRaw.map((id) => id.toString()).toList();
    }
    return List<String>.from(snap.child('players').value as List? ?? [])
        .map((id) => id.toString())
        .toList();
  }

  int? _parseFirebaseTimestamp(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return null;
  }

  bool _shouldSkipClosedRoomKick({
    required bool dataPostGameActive,
    required bool dataSeriesRestarting,
    required int? seriesNextMatchAt,
    dynamic seriesPlayerIdsRaw,
  }) {
    if (dataPostGameActive) return true;
    if (dataSeriesRestarting) return true;
    if (seriesNextMatchAt != null) return true;
    if (_hasRemainingSeriesMatches) return true;
    if (_isInFixedSeriesRoster(seriesPlayerIdsRaw, myId)) return true;
    return false;
  }

  void _maybeTriggerSeriesRestart({
    required int? seriesNextMatchAt,
    required bool dataSeriesRestarting,
  }) {
    if (!isHost || !mounted || _seriesRestartInProgress || dataSeriesRestarting) return;
    if (!_hasRemainingSeriesMatches || seriesNextMatchAt == null) return;
    if (DateTime.now().millisecondsSinceEpoch < seriesNextMatchAt) return;
    _autoContinueSeries();
  }

  void _cancelMoriResolutionTimers() {
    _moriCountdownTimer?.cancel();
    _moriCountdownTimer = null;
    _moriResolutionKey = '';
    _moriResolutionDeadlineMs = null;
    if (_moriCountdownSeconds != null && mounted) {
      setState(() => _moriCountdownSeconds = null);
    } else {
      _moriCountdownSeconds = null;
    }
  }

  String _moriResolutionKeyFromState() =>
      '${lastMoriPlayerId ?? ''}|${moriRevealedType ?? ''}';

  int _moriRemainingSeconds(int nowMs) {
    final deadline = _moriResolutionDeadlineMs;
    if (deadline == null) return RoomConfig.moriResolutionSeconds;
    final remainingMs = deadline - nowMs;
    if (remainingMs <= 0) return 0;
    final seconds = (remainingMs + 999) ~/ 1000;
    return seconds > RoomConfig.moriResolutionSeconds
        ? RoomConfig.moriResolutionSeconds
        : seconds;
  }

  void _tickMoriResolution() {
    if (!mounted || moriPhase != 'mori_declared' || _moriResolutionDeadlineMs == null) {
      _cancelMoriResolutionTimers();
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final remainingSeconds = _moriRemainingSeconds(now);
    if (remainingSeconds != _moriCountdownSeconds) {
      setState(() => _moriCountdownSeconds = remainingSeconds);
    }

    if (isHost && now >= _moriResolutionDeadlineMs! && !_moriFinishRequested) {
      _moriFinishRequested = true;
      _db.updateGameStatus({'moriPhase': 'finished'});
    }
  }

  void _beginMoriResolutionCountdown(String key) {
    if (key == _moriResolutionKey && _moriCountdownTimer != null) return;

    _moriResolutionKey = key;
    _moriFinishRequested = false;
    _moriResolutionDeadlineMs =
        DateTime.now().millisecondsSinceEpoch + RoomConfig.moriResolutionMs;
    _cancelAutoPlayTimer();
    _moriCountdownTimer?.cancel();
    _moriCountdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _tickMoriResolution(),
    );
    if (mounted) {
      setState(() => _moriCountdownSeconds = RoomConfig.moriResolutionSeconds);
    } else {
      _moriCountdownSeconds = RoomConfig.moriResolutionSeconds;
    }
    _tickMoriResolution();
  }

  void _syncMoriResolution() {
    if (moriPhase != 'mori_declared') {
      _cancelMoriResolutionTimers();
      return;
    }

    final key = _moriResolutionKeyFromState();
    if (key == '|') return;
    _beginMoriResolutionCountdown(key);
    if (isHost) _syncAllBotTimers();
  }

  bool _shouldStartInitialPhaseAutoFlip() {
    if (!isHost || !mounted || _postGameClosing || _showPostGameOverlay) return false;
    if (!RoomConfig.hasMinPlayers(playerIds.length)) return false;
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
    _autoPlayDeadlineMs = DateTime.now().millisecondsSinceEpoch + _turnTimeoutMs;
    _autoPlayCountdownSeconds = turnTimeoutSeconds;
    _autoPlayTimer = Timer(Duration(milliseconds: _turnTimeoutMs), _performAutoPlay);
    _autoPlayCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateAutoPlayCountdown();
    });
    if (mounted) {
      setState(() => _autoPlayCountdownSeconds = turnTimeoutSeconds);
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
        handCounts: handCounts,
        lastDrawerId: lastDrawerId,
        isDrawCompetitive: isDrawCompetitive,
        hasPlayedThisTurn: _botHasPlayedThisTurn[botId] ?? false,
        fieldSuit: fieldSuit,
        lastPlayerId: lastPlayerId,
        lastMoriPlayerId: lastMoriPlayerId,
        moriDeclaredPlayerIds: moriDeclaredPlayerIds,
        openJokerPlayerIds: openJokerPlayerIds,
        playerHands: _allPlayerCards,
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

  int _botActionDelayMs({required bool moriDeclaredPhase}) {
    final maxMs = moriDeclaredPhase ? _moriBotDelayMaxMs() : _turnTimeoutMs;
    return BotLogic.randomActionDelayMs(maxMs: maxMs, random: _botRandom);
  }

  int _moriBotDelayMaxMs() {
    const minMs = 400;
    final remaining = _moriResolutionDeadlineMs != null
        ? _moriResolutionDeadlineMs! - DateTime.now().millisecondsSinceEpoch
        : RoomConfig.moriResolutionMs;
    return remaining.clamp(minMs, _turnTimeoutMs);
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
      handCountsSignature: BotLogic.buildHandCountsSignature(
        playerIds,
        handCounts,
        openJokerPlayerIds: openJokerPlayerIds,
        playerHands: _allPlayerCards,
      ),
      lastPlayerId: lastPlayerId,
      lastMoriPlayerId: lastMoriPlayerId,
      moriGaeshiCount: moriGaeshiCount,
      moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      openJokerPlayerIds: openJokerPlayerIds,
    );
    if (_botTimerKeys[botId] == key && _botTimers[botId] != null) return;

    _cancelBotTimer(botId);
    _botTimerKeys[botId] = key;
    final delayMs = _botActionDelayMs(moriDeclaredPhase: moriPhase == 'mori_declared');
    _botTimers[botId] = Timer(
      Duration(milliseconds: delayMs),
      () => _performBotAction(botId),
    );
  }

  void _performBotAction(String botId) {
    _cancelBotTimer(botId);
    if (!_shouldRunBotLogic() || !BotLogic.isBot(botId)) return;

    if (moriPhase == 'mori_declared') {
      _executeBotMoriGaeshi(botId);
      return;
    }

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
      handCounts: handCounts,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      hasPlayedThisTurn: _botHasPlayedThisTurn[botId] ?? false,
      lastPlayerId: lastPlayerId,
      moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      openJokerPlayerIds: openJokerPlayerIds,
      playerHands: _allPlayerCards,
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

    final botId = BotLogic.tryNextBotId(playerIds);
    if (botId == null) {
      _showGameMessage('Botは最大${BotLogic.maxBotSlot}体まで追加できます');
      return;
    }

    final botName = BotLogic.botDisplayName(botId);
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
      'playerPoints/$botId': 0,
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
    if (!isInitialPhase && hand.length == 1) return;

    final card = hand[index];
    final previousFieldNumber = fieldNumber;
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
    fieldNumber = card.number;
    fieldSuit = card.suit;
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
    unawaited(_recordMatchEvent(
      type: MatchEventType.playCard,
      actorId: botId,
      payload: {
        'card': _serializeHand([card]).first,
        'isInitialPhase': isInitialPhase,
      },
      actorHand: hand,
    ));
    _emitCardPlayEffect(
      actorId: botId,
      previousFieldNumber: previousFieldNumber,
      newFieldNumber: card.number,
    );
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
      unawaited(_recordMatchEvent(
        type: MatchEventType.draw,
        actorId: botId,
        payload: {
          'card': _serializeHand([drawn]).first,
          'isSeventhDraw': true,
          'burst': true,
          if (resetMetaUpdates.containsKey('deckResetAt')) 'deckReset': true,
        },
        actorHand: tempHand,
      ));
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
      _emitDrawEffect(actorId: botId);
      return;
    }

    _allPlayerCards[botId] = tempHand;
    unawaited(_recordMatchEvent(
      type: MatchEventType.draw,
      actorId: botId,
      payload: {
        'card': _serializeHand([drawn]).first,
        'isSeventhDraw': isSeventhDraw,
        'isDrawCompetitive': !isSeventhDraw,
        if (resetMetaUpdates.containsKey('deckResetAt')) 'deckReset': true,
      },
      actorHand: tempHand,
    ));
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
    _emitDrawEffect(actorId: botId);
  }

  void _executeBotMori(String botId) {
    final hand = _botHand(botId);
    if (!BotLogic.canDeclareMori(
      fieldNumber: fieldNumber,
      hand: hand,
      moriPhase: moriPhase,
      lastPlayerId: lastPlayerId,
      playerId: botId,
      moriDeclaredPlayerIds: moriDeclaredPlayerIds,
    )) {
      return;
    }

    _db.updateGameStatus({
      'moriPhase': 'mori_declared',
      'moriDeclaredAt': ServerValue.timestamp,
      'lastMoriPlayerId': botId,
      'loserPlayerId': lastPlayerId,
      'moriRevealedHand': _serializeHand(hand),
      'moriRevealedType': 'mori',
      'moriGaeshiCount': 0,
      'moriDeclarationFactors': [ScoringRules.handFactor(hand, openJoker: openJokerPlayerIds.contains(botId))],
      'moriDeclaredPlayerIds': [botId],
    });
    unawaited(_recordMatchEvent(
      type: MatchEventType.mori,
      actorId: botId,
      payload: {
        'hand': _serializeHand(hand),
        'loserId': lastPlayerId,
        'handFactor': _handFactorFor(botId, hand),
      },
      actorHand: hand,
    ));
    _emitMoriEffect(actorId: botId, isGaeshi: false, hand: hand);
  }

  void _executeBotMoriGaeshi(String botId) {
    final hand = _botHand(botId);
    if (!BotLogic.canDeclareMoriGaeshi(
      fieldNumber: fieldNumber,
      hand: hand,
      moriPhase: moriPhase,
      lastMoriPlayerId: lastMoriPlayerId,
      playerId: botId,
      moriDeclaredPlayerIds: moriDeclaredPlayerIds,
    )) {
      return;
    }

    final previousMoriPlayerId = lastMoriPlayerId;
    final nextGaeshiCount = moriGaeshiCount + 1;
    final handFactor = _handFactorFor(botId, hand);
    final nextFactors = [...moriDeclarationFactors, handFactor];
    final nextDeclaredIds = [...moriDeclaredPlayerIds, botId];

    _db.updateGameStatus({
      'moriDeclaredAt': ServerValue.timestamp,
      'lastMoriPlayerId': botId,
      'loserPlayerId': previousMoriPlayerId,
      'moriRevealedHand': _serializeHand(hand),
      'moriRevealedType': 'gaeshi',
      'moriGaeshiCount': nextGaeshiCount,
      'moriDeclarationFactors': nextFactors,
      'moriDeclaredPlayerIds': nextDeclaredIds,
    });
    unawaited(_recordMatchEvent(
      type: MatchEventType.moriGaeshi,
      actorId: botId,
      payload: {
        'hand': _serializeHand(hand),
        'loserId': previousMoriPlayerId,
        'handFactor': handFactor,
        'moriGaeshiCount': nextGaeshiCount,
      },
      actorHand: hand,
    ));
    _emitMoriEffect(actorId: botId, isGaeshi: true, hand: hand);
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
      unawaited(_recordMatchEvent(
        type: MatchEventType.draw,
        actorId: myId,
        payload: {
          'card': _serializeHand([drawn]).first,
          'isSeventhDraw': true,
          'burst': true,
          if (resetMetaUpdates.containsKey('deckResetAt')) 'deckReset': true,
        },
        actorHand: tempHand,
      ));
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
      _emitDrawEffect(actorId: myId);
      return;
    }

    setState(() => myHand.add(drawn));

    // 手札6枚以下: 次のプレイヤーも出す/引く権利（早い者勝ち）。7枚目は競合なし。
    final bool enableDrawCompetition = !isSeventhDraw;
    unawaited(_recordMatchEvent(
      type: MatchEventType.draw,
      actorId: myId,
      payload: {
        'card': _serializeHand([drawn]).first,
        'isSeventhDraw': isSeventhDraw,
        'isDrawCompetitive': enableDrawCompetition,
        if (resetMetaUpdates.containsKey('deckResetAt')) 'deckReset': true,
      },
      actorHand: tempHand,
    ));
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
    _emitDrawEffect(actorId: myId);
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
    _cancelAutoPlayTimer();
    if (isInitialPhase) _cancelInitialPhaseAutoFlipTimer();
    int myIdx = playerIds.indexOf(myId);
    _hasPlayedThisTurn = true;
    setState(() { for (var c in cards) { myHand.removeWhere((h) => h.number == c.number && h.suit == c.suit); } });

    final CardWidget playedCard = cards.last;
    final previousFieldNumber = fieldNumber;
    final updatedHistory = List<CardWidget>.from(fieldHistory)..add(playedCard);
    fieldNumber = playedCard.number;
    fieldSuit = playedCard.suit;
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
    unawaited(_recordMatchEvent(
      type: MatchEventType.playCard,
      actorId: myId,
      payload: {
        'card': _serializeHand([playedCard]).first,
        'isInitialPhase': isInitialPhase,
      },
      actorHand: myHand,
    ));
    _emitCardPlayEffect(
      actorId: myId,
      previousFieldNumber: previousFieldNumber,
      newFieldNumber: playedCard.number,
    );
  }

  void _onMori() {
    if (moriPhase == 'none') {
      if (!GameRules.canDeclareMori(
        fieldNumber: fieldNumber,
        hand: myHand,
        moriPhase: moriPhase,
        lastPlayerId: lastPlayerId,
        playerId: myId,
        moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      )) {
        if (moriDeclaredPlayerIds.contains(myId)) {
          _showGameMessage('もり／もり返しは1回だけ宣言できます');
        } else if (lastPlayerId == myId) {
          _showGameMessage('自滅はできません！');
        } else if (lastPlayerId == 'system') {
          _showGameMessage('山札に対してもりは宣言できません');
        } else {
          _showGameMessage('計算が合いません！');
        }
        return;
      }
    } else if (!GameRules.canDeclareMoriGaeshi(
      fieldNumber: fieldNumber,
      hand: myHand,
      moriPhase: moriPhase,
      lastMoriPlayerId: lastMoriPlayerId,
      playerId: myId,
      moriDeclaredPlayerIds: moriDeclaredPlayerIds,
    )) {
      if (moriDeclaredPlayerIds.contains(myId)) {
        _showGameMessage('もり／もり返しは1回だけ宣言できます');
      } else {
        _showGameMessage('計算が合いません！');
      }
      return;
    }

    final revealedHand = _serializeHand(myHand);
    if (moriPhase == 'none') {
      final handFactor = _handFactorFor(myId, myHand);
      setState(() {
        moriPhase = 'mori_declared';
        lastMoriPlayerId = myId;
        loserPlayerId = lastPlayerId;
        moriRevealedType = 'mori';
        moriRevealedHand = List<CardWidget>.from(myHand);
        moriGaeshiCount = 0;
        moriDeclarationFactors = [handFactor];
        moriDeclaredPlayerIds = [myId];
      });
      _beginMoriResolutionCountdown('$myId|mori');
      _db.updateGameStatus({
        'moriPhase': 'mori_declared',
        'moriDeclaredAt': ServerValue.timestamp,
        'lastMoriPlayerId': myId,
        'loserPlayerId': lastPlayerId,
        'moriRevealedHand': revealedHand,
        'moriRevealedType': 'mori',
        'moriGaeshiCount': 0,
        'moriDeclarationFactors': [handFactor],
        'moriDeclaredPlayerIds': [myId],
      });
      unawaited(_recordMatchEvent(
        type: MatchEventType.mori,
        actorId: myId,
        payload: {
          'hand': revealedHand,
          'loserId': lastPlayerId,
          'handFactor': handFactor,
        },
        actorHand: myHand,
      ));
      _emitMoriEffect(actorId: myId, isGaeshi: false, hand: myHand);
    } else {
      final previousMoriPlayerId = lastMoriPlayerId;
      final nextGaeshiCount = moriGaeshiCount + 1;
      final handFactor = _handFactorFor(myId, myHand);
      final nextFactors = [...moriDeclarationFactors, handFactor];
      final nextDeclaredIds = [...moriDeclaredPlayerIds, myId];
      setState(() {
        lastMoriPlayerId = myId;
        loserPlayerId = previousMoriPlayerId;
        moriRevealedType = 'gaeshi';
        moriRevealedHand = List<CardWidget>.from(myHand);
        moriGaeshiCount = nextGaeshiCount;
        moriDeclarationFactors = nextFactors;
        moriDeclaredPlayerIds = nextDeclaredIds;
      });
      _beginMoriResolutionCountdown('$myId|gaeshi');
      _db.updateGameStatus({
        'moriDeclaredAt': ServerValue.timestamp,
        'lastMoriPlayerId': myId,
        'loserPlayerId': previousMoriPlayerId,
        'moriRevealedHand': revealedHand,
        'moriRevealedType': 'gaeshi',
        'moriGaeshiCount': nextGaeshiCount,
        'moriDeclarationFactors': nextFactors,
        'moriDeclaredPlayerIds': nextDeclaredIds,
      });
      unawaited(_recordMatchEvent(
        type: MatchEventType.moriGaeshi,
        actorId: myId,
        payload: {
          'hand': revealedHand,
          'loserId': previousMoriPlayerId,
          'handFactor': handFactor,
          'moriGaeshiCount': nextGaeshiCount,
        },
        actorHand: myHand,
      ));
      _emitMoriEffect(actorId: myId, isGaeshi: true, hand: myHand);
    }
  }

  List<Map<String, dynamic>> _serializeHand(List<CardWidget> hand) =>
      hand.map((c) => {'number': c.number, 'suit': c.suit.name}).toList();

  Map<String, List<Map<String, dynamic>>> _handsSnapshot({
    String? actorId,
    List<CardWidget>? actorHand,
  }) {
    final snapshot = <String, List<Map<String, dynamic>>>{};
    for (final pid in playerIds) {
      final List<CardWidget> cards;
      if (actorId != null && pid == actorId && actorHand != null) {
        cards = actorHand;
      } else {
        cards = List<CardWidget>.from(_allPlayerCards[pid] ?? []);
      }
      snapshot[pid] = _serializeHand(cards);
    }
    return snapshot;
  }

  int _handFactorFor(String playerId, List<CardWidget> hand) =>
      ScoringRules.handFactor(hand, openJoker: openJokerPlayerIds.contains(playerId));

  void _onOpenJoker() {
    if (!GameRules.canOpenJoker(
      hand: myHand,
      playerId: myId,
      openJokerPlayerIds: openJokerPlayerIds,
      gameStarted: gameStarted,
      moriPhase: moriPhase,
    )) {
      if (openJokerPlayerIds.contains(myId)) {
        _showGameMessage('すでにオープンジョーカーしています');
      } else if (!GameRules.hasJoker(myHand)) {
        _showGameMessage('ジョーカーがないため公開できません');
      } else {
        _showGameMessage('今はオープンジョーカーできません');
      }
      return;
    }

    setState(() => openJokerPlayerIds = {...openJokerPlayerIds, myId});
    _showGameMessage('ジョーカーを公開しました');
    _db.updateGameStatus({'openJokerPlayerIds/$myId': true});
    unawaited(_recordMatchEvent(
      type: MatchEventType.openJoker,
      actorId: myId,
      payload: {
        'jokerPlusOne': GameRules.isJokerPlusOneHand(myHand),
      },
      actorHand: myHand,
    ));
  }

  Future<void> _startMatchRecording({
    List<CardWidget>? deckOverride,
    CardWidget? fieldCard,
  }) async {
    if (!isHost || isSpectator) return;
    try {
      final field = fieldCard ?? CardWidget(number: fieldNumber, suit: fieldSuit);
      final deckCards = deckOverride ?? deck;
      await _matchRecordService.startMatch(
        roomId: widget.roomId,
        matchIndex: _currentMatchNumber,
        seriesTotal: totalMatches,
        turnTimeoutSeconds: turnTimeoutSeconds,
        playerIds: playerIds,
        playerNames: playerNames,
        botIds: playerIds.where(BotLogic.isBot).toList(),
        hands: _handsSnapshot(),
        deck: _serializeHand(deckCards),
        field: MatchRecordCodec.field(field.number, field.suit),
        fieldHistory: fieldHistory
            .map((c) => {'number': c.number, 'suit': c.suit.name})
            .toList(),
        currentTurnIndex: currentTurn,
        isInitialPhase: isInitialPhase,
      );
    } catch (e, st) {
      assert(() {
        debugPrint('試合記録の開始に失敗: $e');
        debugPrint('$st');
        return true;
      }());
    }
  }

  Future<void> _recordMatchEvent({
    required MatchEventType type,
    String? actorId,
    Map<String, dynamic> payload = const {},
    List<CardWidget>? actorHand,
  }) async {
    if (!isHost) return;
    try {
      await _matchRecordService.recordEvent(
        type: type,
        actorId: actorId,
        payload: payload,
        handsSnapshot: _handsSnapshot(actorId: actorId, actorHand: actorHand),
        turnIndex: currentTurn,
        field: MatchRecordCodec.field(fieldNumber, fieldSuit),
      );
    } catch (_) {}
  }

  Future<void> _finalizeMatchRecording() async {
    if (!isHost || !_matchRecordService.isRecording) return;

    var endReason = 'unknown';
    String? winnerId;
    String? loserId;
    if (burstPlayerId != null) {
      endReason = 'burst';
      loserId = burstPlayerId;
    } else if (lastMoriPlayerId != null) {
      endReason = 'mori';
      winnerId = lastMoriPlayerId;
      loserId = loserPlayerId;
    }

    try {
      await _matchRecordService.finalizeMatch(
        MatchRecordResult(
          endReason: endReason,
          winnerId: winnerId,
          loserId: loserId,
          pointDeltas: Map<String, int>.from(_lastMatchPointDeltas),
          moriGaeshiCount: moriGaeshiCount,
          moriDeclarationFactors: List<int>.from(moriDeclarationFactors),
          endedAtMs: DateTime.now().millisecondsSinceEpoch,
        ),
      );
    } catch (_) {}
  }

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
    if (!RoomConfig.hasMinPlayers(playerIds.length)) {
      _showGameMessage('ゲーム開始には${RoomConfig.minPlayers}人以上必要です');
      return;
    }
    _cancelInitialPhaseAutoFlipTimer();
    if (deck.isEmpty) {
      _replenishDeckFromFieldIfEmpty();
      if (deck.isEmpty) return;
    }
    final card = deck.last;
    final updatedHistory = List<CardWidget>.from(fieldHistory)..add(card);
    fieldNumber = card.number;
    fieldSuit = card.suit;
    fieldHistory = updatedHistory;
    final isNewGame = !gameStarted;
    final playOrder =
        isNewGame ? GameRules.shuffledPlayerOrder(playerIds) : playerIds;
    _db.updateGameStatus({
      'field': {'number': card.number, 'suit': card.suit.name},
      'deck': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'deckIndex': deck.sublist(0, deck.length - 1).map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'fieldHistory': updatedHistory.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'isInitialPhase': true,
      'lastPlayerId': 'system',
      'roomStatus': 'closed',
      'gameStarted': true,
      if (isNewGame) ...{
        'players': playOrder,
        'currentTurnIndex': 0,
      },
      if (totalMatches > 1 && completedMatches == 0)
        'seriesPlayerIds': List<String>.from(playOrder),
      'rematchHostRequested': false,
      'postGameActive': false,
      'burstPlayerId': null,
      'moriGaeshiCount': null,
      'moriDeclarationFactors': null,
      'moriDeclaredPlayerIds': null,
      'openJokerPlayerIds': null,
      'lastMatchPointSummary': null,
      'lastMatchPointDeltas': null,
      'seriesRatingApplied': null,
      'seriesRatingSummary': null,
      'seriesRatingDetails': null,
      'lastMoriPlayerId': null,
      'loserPlayerId': null,
      'moriPhase': 'none',
      'moriDeclaredAt': null,
      'moriRevealedHand': null,
      'moriRevealedType': null,
    });
    setState(() {
      _postGameSummary = null;
      _postGameEntered = false;
      _seriesAutoContinueScheduled = false;
      if (isNewGame) {
        playerIds = playOrder;
        currentTurn = 0;
        if (totalMatches > 1 && completedMatches == 0) {
          seriesPlayerIds = List<String>.from(playOrder);
        }
        _showGameMessage('${_displayName(playOrder.first)} から開始（手番順をシャッフル）');
      }
    });
    unawaited(_onFlipRecorded(card, deck.sublist(0, deck.length - 1)));
  }

  Future<void> _onFlipRecorded(CardWidget card, List<CardWidget> deckAfter) async {
    if (!isHost) return;
    if (!_matchRecordService.isRecording) {
      await _startMatchRecording(deckOverride: deckAfter, fieldCard: card);
      return;
    }
    await _recordMatchEvent(
      type: MatchEventType.fieldFlip,
      actorId: 'system',
      payload: {'card': _serializeHand([card]).first},
    );
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
    unawaited(_recordMatchEvent(
      type: MatchEventType.deckReset,
      payload: {
        'deck': _serializeHand(deck),
        'field': MatchRecordCodec.field(fieldNumber, fieldSuit),
      },
    ));
  }

  void _cleanupRoomOnLeave() {
    if (isHost) {
      _closeRoomForcefully();
      return;
    }
    unawaited(_removeSelfFromRoomAndMaybeDelete());
  }

  Future<void> _removeSelfFromRoomAndMaybeDelete() async {
    await _db.removePlayerPresence(myId);
    final p = List<String>.from(playerIds)..remove(myId);
    await _db.updateGameStatus({
      'players': p,
      'playerHands/$myId': null,
      'playerCards/$myId': null,
      'playerNames/$myId': null,
    });
    await _db.deleteRoomIfAbandoned();
  }

  void _closeRoomForcefully({bool dismissedByHost = false}) {
    if (isHost) {
      unawaited(_cancelHostDisconnectClose());
    }
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
    _seriesContinueTimer?.cancel();
    _seriesContinueTimer = null;
    _seriesUiCountdownTimer?.cancel();
    _seriesUiCountdownTimer = null;
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

  Future<void> _finalizeRematchWithPlayers(
    List<String> players, {
    bool forSeriesContinue = false,
  }) async {
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
      forSeriesContinue: forSeriesContinue,
    );

    if (!mounted) return;
    setState(() {
      _postGameSummary = null;
      _postGameEntered = false;
      awaitingGuestStayResponses = false;
      rematchEligiblePlayers = [];
      rematchReadyMap = {};
      myStayResponseSubmitted = false;
      postGameActive = false;
      gameStarted = false;
      roomStatus = forSeriesContinue ? 'closed' : 'open';
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
      if (!forSeriesContinue) {
        completedMatches = 0;
        seriesPlayerIds = [];
        _lastMatchPointDeltas = {};
        _seriesRatingDetails = {};
        playerPoints = {for (final p in players) p: 0};
        _seriesAutoContinueScheduled = false;
        _seriesRestartInProgress = false;
      }
    });
    if (!forSeriesContinue) {
      _showGameMessage('ルームを公開しました。参加者が揃ったら山札をめくってください。');
    }
  }

  void _syncPostGameSummary() {
    if (!_postGameEntered) return;

    final roster = seriesPlayerIds.isNotEmpty
        ? List<String>.from(seriesPlayerIds)
        : List<String>.from(playerIds);
    final names = {for (final id in roster) id: _displayName(id)};
    final seriesComplete = totalMatches <= 1 || completedMatches >= totalMatches;

    final summary = PostGameSummaryBuilder.build(
      roster: roster,
      names: names,
      playerPoints: playerPoints,
      lastMatchPointDeltas: _lastMatchPointDeltas,
      seriesRatingDetails: _seriesRatingDetails,
      totalMatches: totalMatches,
      completedMatches: completedMatches,
      seriesComplete: seriesComplete,
      resultMessage: burstPlayerId != null
          ? ScoringRules.describeBurstScoring(burstPlayerName: _displayName(burstPlayerId))
          : null,
    );

    if (mounted) setState(() => _postGameSummary = summary);
  }

  void _enterPostGame() {
    if (_postGameEntered) return;
    _postGameEntered = true;
    _syncPostGameSummary();
    if (isHost) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onHostPostGameEntered());
    }
  }

  Future<void> _applyMatchScoring() async {
    if (!isHost) return;

    final updatedPoints = Map<String, int>.from(playerPoints);
    for (final pid in playerIds) {
      updatedPoints.putIfAbsent(pid, () => 0);
    }

    final matchDeltas = <String, int>{};
    String? summary;
    if (burstPlayerId != null) {
      final penalty = ScoringRules.burstPenalty();
      updatedPoints[burstPlayerId!] = (updatedPoints[burstPlayerId!] ?? 0) - penalty;
      matchDeltas[burstPlayerId!] = -penalty;
      summary = ScoringRules.describeBurstScoring(
        burstPlayerName: _displayName(burstPlayerId),
      );
    } else if (lastMoriPlayerId != null &&
        loserPlayerId != null &&
        moriDeclarationFactors.isNotEmpty) {
      final delta = ScoringRules.moriWinnerDelta(moriDeclarationFactors, moriGaeshiCount);
      updatedPoints[lastMoriPlayerId!] = (updatedPoints[lastMoriPlayerId!] ?? 0) + delta;
      updatedPoints[loserPlayerId!] = (updatedPoints[loserPlayerId!] ?? 0) - delta;
      matchDeltas[lastMoriPlayerId!] = delta;
      matchDeltas[loserPlayerId!] = -delta;
      summary = ScoringRules.describeMoriScoring(
        winnerName: _displayName(lastMoriPlayerId),
        loserName: _displayName(loserPlayerId),
        declarationFactors: moriDeclarationFactors,
        moriGaeshiCount: moriGaeshiCount,
        delta: delta,
      );
    }

    if (summary == null) return;

    _lastMatchPointDeltas = matchDeltas;
    await _db.updateGameStatus({
      'playerPoints': updatedPoints,
      'lastMatchPointSummary': summary,
      'lastMatchPointDeltas': matchDeltas,
    });
    playerPoints = updatedPoints;
    if (mounted) _syncPostGameSummary();
    await _finalizeMatchRecording();
  }

  Future<void> _onHostPostGameEntered() async {
    await _applyMatchScoring();
    await _db.markPostGameStarted();

    final willCompleteSeries = totalMatches <= 1 || completedMatches + 1 >= totalMatches;

    if (totalMatches <= 1) {
      if (willCompleteSeries) await _applySeriesRatingUpdate();
      return;
    }

    final nextCompleted = completedMatches + 1;
    final deadline = DateTime.now().millisecondsSinceEpoch + RoomConfig.seriesNextMatchMs;
    final updates = <String, dynamic>{
      'completedMatches': nextCompleted,
    };
    if (nextCompleted < totalMatches) {
      updates['seriesNextMatchAt'] = deadline;
      if (seriesPlayerIds.isEmpty) {
        updates['seriesPlayerIds'] = List<String>.from(playerIds);
      }
    } else {
      updates['seriesNextMatchAt'] = null;
      updates['seriesRestarting'] = false;
      updates['seriesPlayerIds'] = null;
    }
    await _db.updateGameStatus(updates);
    completedMatches = nextCompleted;

    if (nextCompleted < totalMatches) {
      _scheduleSeriesAutoContinue(deadline);
      return;
    }

    await _applySeriesRatingUpdate();
    if (mounted) _syncPostGameSummary();
  }

  void _syncSeriesContinueUi(int deadlineMs) {
    if (!_postGameEntered || !_hasRemainingSeriesMatches) return;
    if (_seriesUiCountdownTimer != null) return;

    _seriesUiCountdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _updateSeriesContinueCountdown(deadlineMs);
    });
    _updateSeriesContinueCountdown(deadlineMs);
  }

  void _scheduleSeriesAutoContinue(int deadlineMs) {
    if (!isHost || _seriesAutoContinueScheduled || !_hasRemainingSeriesMatches) return;
    _seriesAutoContinueScheduled = true;
    _syncSeriesContinueUi(deadlineMs);
    _seriesContinueTimer?.cancel();
    final delay = deadlineMs - DateTime.now().millisecondsSinceEpoch;
    _seriesContinueTimer = Timer(
      Duration(milliseconds: delay > 0 ? delay : 0),
      _autoContinueSeries,
    );
  }

  void _updateSeriesContinueCountdown(int deadlineMs) {
    final remaining =
        ((deadlineMs - DateTime.now().millisecondsSinceEpoch) / 1000).ceil();
    final clamped = remaining < 0 ? 0 : remaining;
    if (clamped > RoomConfig.seriesNextMatchSeconds) {
      return;
    }
    if (clamped != _countdownSeconds && mounted) {
      setState(() => _countdownSeconds = clamped);
    }
  }

  Future<void> _autoContinueSeries() async {
    if (!isHost || !mounted || _seriesRestartInProgress) return;
    if (!_hasRemainingSeriesMatches) return;

    _seriesRestartInProgress = true;
    _seriesAutoContinueScheduled = false;
    _cancelPostGameTimers();

    try {
      await _db.updateGameStatus({'seriesRestarting': true});

      final snap = await _db.getSnapshot();
      if (!snap.exists || !mounted) return;

      final roster = GameRules.shuffledPlayerOrder(
        _readSeriesRosterFromSnapshot(snap),
      );

      if (!RoomConfig.hasMinPlayers(roster.length)) {
        await _db.updateGameStatus({
          'seriesRestarting': false,
          'seriesNextMatchAt': null,
        });
        await _closeRoomAndExitLobby();
        return;
      }

      final deckCards = _generateDeck()..shuffle();
      final playerCards = <String, List<Map<String, dynamic>>>{};
      final playerHandCounts = <String, int>{};

      for (final pid in roster) {
        final hand = <CardWidget>[];
        for (int i = 0; i < 5; i++) {
          if (deckCards.isNotEmpty) hand.add(deckCards.removeLast());
        }
        playerCards[pid] = _serializeHand(hand);
        playerHandCounts[pid] = hand.length;
      }

      if (deckCards.isEmpty) {
        await _db.updateGameStatus({
          'seriesRestarting': false,
          'seriesNextMatchAt': null,
        });
        return;
      }

      final firstCard = deckCards.removeLast();
      final remainingDeck =
          deckCards.map((c) => {'number': c.number, 'suit': c.suit.name}).toList();
      final fieldHistoryData = [
        {'number': firstCard.number, 'suit': firstCard.suit.name},
      ];

      await _db.startSeriesNextMatch(
        players: roster,
        playerCards: playerCards,
        playerHands: playerHandCounts,
        deck: remainingDeck,
        field: {'number': firstCard.number, 'suit': firstCard.suit.name},
        fieldHistory: fieldHistoryData,
      );

      if (!mounted) return;
      setState(() {
        playerIds = roster;
        seriesPlayerIds = roster;
        _postGameSummary = null;
        _postGameEntered = false;
        awaitingGuestStayResponses = false;
        rematchEligiblePlayers = [];
        rematchReadyMap = {};
        myStayResponseSubmitted = false;
        postGameActive = false;
        gameStarted = true;
        roomStatus = 'closed';
        isInitialPhase = true;
        fieldNumber = firstCard.number;
        fieldSuit = firstCard.suit;
        fieldHistory = [firstCard];
        deck = List<CardWidget>.from(deckCards);
        myHand = (playerCards[myId] ?? [])
            .map((i) => CardWidget(
                  number: i['number'] as int,
                  suit: Suit.values.firstWhere((e) => e.name == i['suit']),
                ))
            .toList();
        _hasPlayedThisTurn = false;
      });
      if (isHost) {
        for (final pid in roster.where(BotLogic.isBot)) {
          _allPlayerCards[pid] = _parseHandFromFirebase(playerCards[pid]);
          _botHasPlayedThisTurn[pid] = false;
        }
        unawaited(_startMatchRecording(
          deckOverride: List<CardWidget>.from(deckCards),
          fieldCard: firstCard,
        ));
      }
      _showGameMessage(
        '第$_currentMatchNumber戦を開始（${_displayName(roster.first)} から）',
      );
    } catch (_) {
      if (mounted) {
        await _db.updateGameStatus({
          'seriesRestarting': false,
          'seriesNextMatchAt': null,
        });
      }
    } finally {
      _seriesRestartInProgress = false;
    }
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
    if (_hasRemainingSeriesMatches) return;
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
      if (mounted) {
        setState(() {
          _postGameSummary = null;
          _postGameEntered = false;
        });
      }
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

    if (isSpectator) {
      await _db.leaveAsSpectator(myId);
    } else {
      await _db.removePlayerPresence(myId);
      final p = List<String>.from(playerIds)..remove(myId);
      final updates = <String, dynamic>{
        'players': p,
        'playerHands/$myId': null,
        'playerCards/$myId': null,
        'playerNames/$myId': null,
        'rematchReady/$myId': null,
      };
      await _db.updateGameStatus(updates);
      await _db.deleteRoomIfAbandoned();
    }

    if (!mounted) return;
    Navigator.popUntil(context, (r) => r.isFirst);
  }

  void _noopCardTap(int _) {}
  void _noop() {}

  Future<void> _applySeriesRatingUpdate() async {
    if (!isHost) return;

    final roster = seriesPlayerIds.isNotEmpty
        ? List<String>.from(seriesPlayerIds)
        : List<String>.from(playerIds);
    if (roster.length < 2) return;

    final finalPoints = Map<String, int>.from(playerPoints);
    for (final pid in roster) {
      finalPoints.putIfAbsent(pid, () => 0);
    }

    final displayNames = <String, String>{
      for (final pid in roster) pid: _displayNameForRating(pid),
    };

    final result = await _ratingService.applySeriesRating(
      roomId: widget.roomId,
      participantIds: roster,
      finalPoints: finalPoints,
      displayNames: displayNames,
    );

    if (result == null || !mounted) return;
    _syncPostGameSummary();
  }

  String _displayNameForRating(String playerId) {
    return PlayerDisplayName.resolveForRating(
      playerId: playerId,
      playerIds: playerIds,
      playerNames: playerNames,
    );
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
    return PlayerDisplayName.resolve(
      playerId: playerId,
      playerIds: playerIds,
      myId: myId,
      playerNames: playerNames,
      hostId: hostId,
      hideOpponentNames: _hideOpponentNames,
    );
  }

  void _showErrorDialog(String msg) { showDialog(context: context, barrierDismissible: false, builder: (_) => AlertDialog(title: const Text("入室エラー"), content: Text(msg), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("戻る"))])); }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        GameBoardView(
      roomId: widget.roomId, fieldNumber: fieldNumber, fieldSuit: fieldSuit, myHand: myHand, playerIds: playerIds, myId: myId,
      playerNames: playerNames,
      playerPoints: playerPoints,
      handCounts: handCounts, currentTurnIndex: currentTurn, isHost: isHost, hostId: hostId, lastPlayerId: lastPlayerId, isInitialPhase: isInitialPhase,
      moriPhase: moriPhase, moriDeclaredPlayerIds: moriDeclaredPlayerIds, lastDrawerId: lastDrawerId, isDrawCompetitive: isDrawCompetitive,
      lastMoriPlayerId: lastMoriPlayerId, moriRevealedHand: moriRevealedHand, moriRevealedType: moriRevealedType,
      playerCount: playerIds.length,
      maxPlayers: maxPlayers,
      gameStarted: gameStarted,
      isSpectator: isSpectator,
      spectatorNames: spectatorNames,
      allPlayerHands: isSpectator ? _spectatorPlayerCards : const {},
      matchProgressLabel: _matchProgressLabel,
      seriesAutoContinuing: _showPostGameOverlay && _hasRemainingSeriesMatches,
      statusMessage: _statusMessage,
      autoPlayCountdownSeconds: _autoPlayCountdownSeconds,
      moriCountdownSeconds: _moriCountdownSeconds,
      postGameVisible: _showPostGameOverlay,
      postGameSummary: _postGameSummary,
      postGameCountdownSeconds: _countdownSeconds,
      awaitingGuestStayResponses: awaitingGuestStayResponses,
      guestStayReadyCount: _guestStayReadyCount(),
      guestStayTotalCount: rematchEligiblePlayers.length,
      guestCountdownSeconds: _guestCountdownSeconds,
      mustRespondToStay: !isSpectator &&
          !isHost &&
          awaitingGuestStayResponses &&
          rematchEligiblePlayers.contains(myId) &&
          !myStayResponseSubmitted,
      myStayResponseSubmitted: myStayResponseSubmitted,
      onHostRematch: isSpectator ? _noop : () => _onUiButtonPress(() { unawaited(_onHostRematchRequest()); }),
      onHostReturnToLobby: isSpectator ? _noop : () => _onUiButtonPress(_onHostReturnToLobby),
      onGuestStayInRoom: isSpectator ? _noop : () => _onUiButtonPress(_onGuestStayInRoom),
      onLeaveToLobby: () => _onUiButtonPress(_leaveRoomToLobby),
      canAddBot: !isSpectator &&
          isHost &&
          !gameStarted &&
          !RoomConfig.isRoomFull(playerIds.length, maxPlayers) &&
          BotLogic.hasAvailableBotSlot(playerIds),
      onAddBot: isSpectator ? null : () => _onUiButtonPress(_addBot),
      hideOpponentNames: _hideOpponentNames,
      onToggleHideOpponentNames: _toggleHideOpponentNames,
      onCardTap: isSpectator ? _noopCardTap : _onCardTap,
      onMori: isSpectator ? _noop : () => _onUiButtonPress(_onMori),
      onOpenJoker: isSpectator ? _noop : () => _onUiButtonPress(_onOpenJoker),
      openJokerPlayerIds: openJokerPlayerIds,
      onDraw: isSpectator ? _noop : () => _onUiButtonPress(_onDraw),
      onFlip: isSpectator ? _noop : () => _onUiButtonPress(_onFlip),
        ),
        GameEffectsOverlay(effects: _gameEffects),
      ],
    );
  }
}