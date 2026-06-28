import 'dart:math';

import 'package:firebase_database/firebase_database.dart';
import '../features/game/game_board_view.dart';
import '../logic/room_config.dart';

/// Firebaseとの通信をカプセル化。
class FirebaseDB {
  final String roomId;
  late final DatabaseReference _roomRef;

  FirebaseDB(this.roomId) {
    _roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
  }

  Stream<DatabaseEvent> get roomStream => _roomRef.onValue;

  Map<String, dynamic> _newRoomPayload(
    String myId,
    List<CardWidget> deck,
    bool isPrivate, {
    required String playerName,
    required int maxPlayers,
    required int totalMatches,
    required int turnTimeoutSeconds,
    required int morrieRate,
    required int minMorrieBalance,
    required List<Map<String, dynamic>> deckIndex,
    required List<Map<String, dynamic>> initialHand,
  }) {
    return {
      'host': myId,
      'players': [myId],
      'maxPlayers': maxPlayers,
      'totalMatches': totalMatches,
      'turnTimeoutSeconds': turnTimeoutSeconds,
      'morrieRate': morrieRate,
      'minMorrieBalance': minMorrieBalance,
      'completedMatches': 0,
      'playerNames': {myId: playerName},
      'playerHands': {myId: 5},
      'playerCards': {myId: initialHand},
      'playerPoints': {myId: 0},
      'deck': deck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'deckIndex': deckIndex,
      'field': {'number': -1, 'suit': 'joker'},
      'isInitialPhase': true,
      'currentTurnIndex': 0,
      'isDrawCompetitive': false,
      'deckResetAt': null,
      'gameStarted': false,
      'isPrivate': isPrivate,
      'roomStatus': 'open',
      'fieldHistory': [],
      'seriesRestarting': false,
      'seriesNextMatchAt': null,
      'presence': {myId: ServerValue.timestamp},
      'createdAt': ServerValue.timestamp,
    };
  }

  /// 既存ルームを上書きせず、空き ID のみに作成する
  Future<bool> trySetupRoom(
    String myId,
    List<CardWidget> deck,
    bool isPrivate, {
    required String playerName,
    required int maxPlayers,
    required int totalMatches,
    required int turnTimeoutSeconds,
    required int morrieRate,
    required int minMorrieBalance,
    required List<Map<String, dynamic>> deckIndex,
    required List<Map<String, dynamic>> initialHand,
  }) async {
    final payload = _newRoomPayload(
      myId,
      deck,
      isPrivate,
      playerName: playerName,
      maxPlayers: maxPlayers,
      totalMatches: totalMatches,
      turnTimeoutSeconds: turnTimeoutSeconds,
      morrieRate: morrieRate,
      minMorrieBalance: minMorrieBalance,
      deckIndex: deckIndex,
      initialHand: initialHand,
    );
    final result = await _roomRef.runTransaction((current) {
      if (current != null) return Transaction.abort();
      return Transaction.success(payload);
    });
    return result.committed;
  }

  Future<void> setupRoom(
    String myId,
    List<CardWidget> deck,
    bool isPrivate, {
    required String playerName,
    required int maxPlayers,
    required int totalMatches,
    required int turnTimeoutSeconds,
    required int morrieRate,
    required int minMorrieBalance,
    required List<Map<String, dynamic>> deckIndex,
    required List<Map<String, dynamic>> initialHand,
  }) async {
    final created = await trySetupRoom(
      myId,
      deck,
      isPrivate,
      playerName: playerName,
      maxPlayers: maxPlayers,
      totalMatches: totalMatches,
      turnTimeoutSeconds: turnTimeoutSeconds,
      morrieRate: morrieRate,
      minMorrieBalance: minMorrieBalance,
      deckIndex: deckIndex,
      initialHand: initialHand,
    );
    if (!created) {
      throw StateError('Room $roomId already exists');
    }
  }

  /// 既存ルームと衝突しない 4 桁 ID を割り当てる
  static Future<String> allocateUniqueRoomId() async {
    final ref = FirebaseDatabase.instance.ref('rooms');
    final random = Random();
    for (var attempt = 0; attempt < 20; attempt++) {
      final id = '${1000 + random.nextInt(9000)}';
      final snap = await ref.child(id).get();
      if (!snap.exists) return id;
    }
    throw StateError('Failed to allocate a unique room id');
  }

  /// 接続中プレイヤーとして登録（切断時に presence 削除 + 離脱扱い）
  Future<void> registerPlayerPresence(String playerId) async {
    final presenceRef = _roomRef.child('presence/$playerId');
    final afkRef = _roomRef.child('afkPlayerIds/$playerId');
    await afkRef.onDisconnect().set(true);
    await presenceRef.onDisconnect().remove();
    await presenceRef.set(ServerValue.timestamp);
    await afkRef.remove();
  }

  Future<void> removePlayerPresence(String playerId) async {
    final presenceRef = _roomRef.child('presence/$playerId');
    final afkRef = _roomRef.child('afkPlayerIds/$playerId');
    try {
      await presenceRef.onDisconnect().cancel();
      await afkRef.onDisconnect().cancel();
    } catch (_) {
      // 未接続など
    }
    await presenceRef.remove();
  }

  /// 意図的な退室・切断時: プレイヤーデータは残し離脱フラグのみ立てる
  Future<void> markPlayerAfk(String playerId) async {
    await _roomRef.child('afkPlayerIds/$playerId').set(true);
    await removePlayerPresence(playerId);
  }

  /// 復帰時に離脱フラグを解除する
  Future<void> clearPlayerAfk(String playerId) async {
    await _roomRef.child('afkPlayerIds/$playerId').remove();
  }

  static const int automationLeaseMs = 20000;

  /// 接続者がいないルームの Bot 進行を1クライアントだけが担当する
  Future<bool> tryClaimAutomationLease(String runnerId) async {
    final ref = _roomRef.child('automationLease');
    final now = DateTime.now().millisecondsSinceEpoch;
    final snap = await ref.get();
    if (!snap.exists || snap.value is! Map) {
      await ref.set({
        'runnerId': runnerId,
        'expiresAt': now + automationLeaseMs,
      });
      return true;
    }
    final map = Map<dynamic, dynamic>.from(snap.value as Map);
    final expiresRaw = map['expiresAt'];
    final expires = expiresRaw is num ? expiresRaw.round() : 0;
    final existingRunner = map['runnerId']?.toString();
    if (expires >= now && existingRunner != null && existingRunner != runnerId) {
      return false;
    }
    await ref.set({
      'runnerId': runnerId,
      'expiresAt': now + automationLeaseMs,
    });
    return true;
  }

  Future<void> releaseAutomationLease(String runnerId) async {
    final ref = _roomRef.child('automationLease');
    final snap = await ref.get();
    if (!snap.exists || snap.value is! Map) return;
    final map = Map<dynamic, dynamic>.from(snap.value as Map);
    if (map['runnerId']?.toString() == runnerId) {
      await ref.remove();
    }
  }

  Future<void> playCard(int nextTurn, CardWidget card, String myId) async {
    await _roomRef.update({
      'field': {'number': card.number, 'suit': card.suit.name},
      'isInitialPhase': false,
      'currentTurnIndex': nextTurn,
      'lastPlayerId': myId,
    });
  }

  Future<void> updateGameStatus(Map<String, dynamic> updates) => _roomRef.update(updates);
  Future<DataSnapshot> getSnapshot() => _roomRef.get();

  /// シリーズ終了精算を Cloud Functions に依頼する
  Future<void> requestSeriesSettlement() async {
    await _roomRef.update({
      'settlementRequested': true,
      'settlementError': null,
    });
  }

  /// Cloud Functions の精算完了を待つ（タイムアウト時は false）
  Future<bool> waitForSeriesSettlement({
    Duration timeout = const Duration(seconds: 45),
    Duration pollInterval = const Duration(milliseconds: 400),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final snap = await _roomRef.get();
      if (!snap.exists) return false;
      final data = snap.value;
      if (data is! Map) return false;
      final room = Map<dynamic, dynamic>.from(data);

      final ratingDone = room['seriesRatingApplied'] == true;
      final morrieRate = RoomConfig.resolveMorrieRate(room['morrieRate']);
      final morrieDone = morrieRate <= 0 || room['seriesMorrieSettled'] == true;
      if (ratingDone && morrieDone) return true;

      if (room['settlementError'] != null) return false;
      await Future<void>.delayed(pollInterval);
    }
    return false;
  }
  Future<void> joinAsSpectator(String spectatorId, String spectatorName) async {
    await _roomRef.child('spectators/$spectatorId').set(spectatorName);
  }

  Future<void> leaveAsSpectator(String spectatorId) async {
    await _roomRef.child('spectators/$spectatorId').remove();
  }

  Future<void> setStayInRoom(String playerId) =>
      _roomRef.child('rematchReady/$playerId').set(true);

  /// 再戦意思確認で「ロビーへ戻る」を選んだゲストが不参加を記録する
  Future<void> declineRematch(String playerId) =>
      _roomRef.child('rematchReady/$playerId').set(false);

  /// ホストが再戦を選んだ直後：既存ゲストの残存意思を集める（ルームはまだ閉鎖）
  Future<void> requestHostRematch(List<String> eligibleGuestIds) async {
    await _roomRef.update({
      'rematchHostRequested': true,
      'awaitingGuestStayResponses': true,
      'rematchEligiblePlayers': eligibleGuestIds,
      'rematchStartedAt': ServerValue.timestamp,
      'rematchReady': null,
      'postGameActive': false,
      'postGameEndedAt': null,
      'roomStatus': 'closed',
    });
  }

  Future<void> markPostGameStarted() async {
    await _roomRef.update({
      'postGameActive': true,
      'postGameEndedAt': ServerValue.timestamp,
      'rematchHostRequested': false,
      'rematchDeadline': null,
      'rematchReady': null,
      'roomDismissedByHost': false,
      'roomStatus': 'closed',
    });
  }

  /// ホストがルーム閉鎖を選んだとき、他プレイヤーへ通知する
  Future<void> dismissRoomByHost() async {
    await _roomRef.update({
      'roomDismissedByHost': true,
      'roomStatus': 'closed',
      'gameStarted': false,
      'postGameActive': false,
      'postGameEndedAt': null,
      'awaitingGuestStayResponses': false,
      'rematchHostRequested': false,
      'seriesNextMatchAt': null,
      'seriesRestarting': false,
    });
  }

  /// ホストが再戦を選んだとき：ゲームをロビー状態に戻し、ルームを公開する
  Future<void> prepareRematchLobby({
    required List<String> players,
    required Map<String, List<Map<String, dynamic>>> playerCards,
    required Map<String, int> playerHands,
    required List<Map<String, dynamic>> deck,
    bool forSeriesContinue = false,
  }) async {
    final updates = <String, dynamic>{
      'players': players,
      'playerCards': playerCards,
      'playerHands': playerHands,
      'deck': deck,
      'deckIndex': deck,
      'field': {'number': -1, 'suit': 'joker'},
      'fieldHistory': [],
      'isInitialPhase': true,
      'currentTurnIndex': 0,
      'gameStarted': false,
      if (!forSeriesContinue) 'isPrivate': false,
      'roomStatus': forSeriesContinue ? 'closed' : 'open',
      'postGameActive': false,
      'postGameEndedAt': null,
      'rematchHostRequested': forSeriesContinue ? false : true,
      'awaitingGuestStayResponses': false,
      'rematchEligiblePlayers': null,
      'rematchStartedAt': null,
      'rematchDeadline': null,
      'rematchReady': null,
      'moriPhase': 'none',
      'moriDeclaredAt': null,
      'lastMoriPlayerId': null,
      'loserPlayerId': null,
      'moriRevealedHand': null,
      'moriRevealedType': null,
      'burstPlayerId': null,
      'morrieBurstPlayerId': null,
      'morrieBurstRecoveryApplied': null,
      'moriGaeshiCount': null,
      'moriDeclarationFactors': null,
      'moriDeclaredPlayerIds': null,
      'openJokerPlayerIds': null,
      'lastMatchPointSummary': null,
      'lastMatchPointDeltas': null,
      'lastMatchMorrieApplied': null,
      'lastMatchMorrieDeltas': null,
      'lastMatchMorrieSummary': null,
      'lastMatchMorrieBalances': null,
      'seriesRatingApplied': null,
      'seriesRatingSummary': null,
      'seriesRatingDetails': null,
      'seriesMorrieSettled': null,
      'seriesMorrieSummary': null,
      'seriesMorrieDetails': null,
      'settlementRequested': null,
      'settlementError': null,
      'settlementCompletedAt': null,
      'postGameSeriesAdvanced': null,
      'lastDrawerId': null,
      'lastPlayerId': null,
      'isDrawCompetitive': false,
      'deckResetAt': null,
    };

    if (!forSeriesContinue) {
      updates['completedMatches'] = 0;
      updates['seriesNextMatchAt'] = null;
      updates['seriesRestarting'] = false;
      updates['seriesPlayerIds'] = null;
      updates['playerPoints'] = {for (final p in players) p: 0};
      updates['playerMorrieSeriesDeltas'] = null;
    }

    await _roomRef.update(updates);
  }

  /// シリーズ対戦の次の1戦を、ロビー経由せず1回の更新で開始する。
  /// 手札の配布まで行い、山札のめくりはホストが行う。
  Future<void> startSeriesNextMatch({
    required List<String> players,
    required Map<String, List<Map<String, dynamic>>> playerCards,
    required Map<String, int> playerHands,
    required List<Map<String, dynamic>> deck,
  }) async {
    await _roomRef.update({
      'players': players,
      'playerCards': playerCards,
      'playerHands': playerHands,
      'deck': deck,
      'deckIndex': deck,
      'field': {'number': -1, 'suit': 'joker'},
      'fieldHistory': [],
      'isInitialPhase': true,
      'currentTurnIndex': 0,
      'gameStarted': false,
      'roomStatus': 'open',
      'postGameActive': false,
      'postGameEndedAt': null,
      'rematchHostRequested': false,
      'awaitingGuestStayResponses': false,
      'rematchEligiblePlayers': null,
      'rematchStartedAt': null,
      'rematchDeadline': null,
      'rematchReady': null,
      'moriPhase': 'none',
      'moriDeclaredAt': null,
      'lastMoriPlayerId': null,
      'loserPlayerId': null,
      'moriRevealedHand': null,
      'moriRevealedType': null,
      'burstPlayerId': null,
      'morrieBurstPlayerId': null,
      'morrieBurstRecoveryApplied': null,
      'moriGaeshiCount': null,
      'moriDeclarationFactors': null,
      'moriDeclaredPlayerIds': null,
      'openJokerPlayerIds': null,
      'lastMatchPointSummary': null,
      'lastMatchPointDeltas': null,
      'lastMatchMorrieApplied': null,
      'lastMatchMorrieDeltas': null,
      'lastMatchMorrieSummary': null,
      'lastMatchMorrieBalances': null,
      'seriesRatingApplied': null,
      'seriesRatingSummary': null,
      'seriesRatingDetails': null,
      'seriesMorrieSettled': null,
      'seriesMorrieSummary': null,
      'seriesMorrieDetails': null,
      'settlementRequested': null,
      'settlementError': null,
      'settlementCompletedAt': null,
      'postGameSeriesAdvanced': null,
      'lastDrawerId': null,
      'lastPlayerId': null,
      'isDrawCompetitive': false,
      'deckResetAt': null,
      'seriesRestarting': false,
      'seriesNextMatchAt': null,
    });
  }

  Future<void> closeRoomForGameStart() async {
    await _roomRef.update({
      'roomStatus': 'closed',
      'gameStarted': true,
    });
  }

  /// 全員の準備が揃ったらホストが呼び、同じメンバーでゲームを初期化する。
  Future<void> restartGame({
    required List<String> players,
    required Map<String, List<Map<String, dynamic>>> rematchHands,
    required List<Map<String, dynamic>> remainingDeck,
    required List<Map<String, dynamic>> deckIndex,
    required int rematchGeneration,
  }) async {
    await _roomRef.update({
      'players': players,
      'playerHands': {for (final p in players) p: 5},
      'playerCards': rematchHands,
      'deck': remainingDeck,
      'deckIndex': deckIndex,
      'rematchHands': rematchHands,
      'rematchGeneration': rematchGeneration,
      'field': {'number': -1, 'suit': 'joker'},
      'isInitialPhase': true,
      'currentTurnIndex': 0,
      'gameStarted': true,
      'moriPhase': 'none',
      'moriDeclaredAt': null,
      'lastMoriPlayerId': null,
      'loserPlayerId': null,
      'moriRevealedHand': null,
      'moriRevealedType': null,
      'burstPlayerId': null,
      'morrieBurstPlayerId': null,
      'morrieBurstRecoveryApplied': null,
      'moriGaeshiCount': null,
      'moriDeclarationFactors': null,
      'moriDeclaredPlayerIds': null,
      'openJokerPlayerIds': null,
      'lastMatchPointSummary': null,
      'lastMatchPointDeltas': null,
      'lastMatchMorrieApplied': null,
      'lastMatchMorrieDeltas': null,
      'lastMatchMorrieSummary': null,
      'lastMatchMorrieBalances': null,
      'seriesRatingApplied': null,
      'seriesRatingSummary': null,
      'seriesRatingDetails': null,
      'seriesMorrieSettled': null,
      'seriesMorrieSummary': null,
      'seriesMorrieDetails': null,
      'settlementRequested': null,
      'settlementError': null,
      'settlementCompletedAt': null,
      'postGameSeriesAdvanced': null,
      'lastDrawerId': null,
      'lastPlayerId': null,
      'isDrawCompetitive': false,
      'deckResetAt': null,
      'fieldHistory': [],
      'rematchReady': null,
      'rematchHostRequested': false,
      'rematchDeadline': null,
      'postGameActive': false,
      'postGameEndedAt': null,
      'roomStatus': 'open',
    });
  }
}