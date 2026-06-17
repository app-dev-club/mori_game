import 'package:firebase_database/firebase_database.dart';
import '../features/game/game_board_view.dart';

/// Firebaseとの通信をカプセル化。
class FirebaseDB {
  final String roomId;
  late final DatabaseReference _roomRef;

  FirebaseDB(this.roomId) {
    _roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
  }

  Stream<DatabaseEvent> get roomStream => _roomRef.onValue;

  Future<void> setupRoom(
    String myId,
    List<CardWidget> deck,
    bool isPrivate, {
    required String playerName,
    required int maxPlayers,
    required int totalMatches,
    required List<Map<String, dynamic>> deckIndex,
    required List<Map<String, dynamic>> initialHand,
  }) async {
    await _roomRef.set({
      'host': myId,
      'players': [myId],
      'maxPlayers': maxPlayers,
      'totalMatches': totalMatches,
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
      // 万が一の残存バグを防ぐため、作成日時をタイムスタンプで記録
      'createdAt': ServerValue.timestamp, 
    });
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
  Future<void> deleteRoom() => _roomRef.remove();

  Future<void> setStayInRoom(String playerId) =>
      _roomRef.child('rematchReady/$playerId').set(true);

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
      'postGameActive': false,
      'awaitingGuestStayResponses': false,
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
      'moriGaeshiCount': null,
      'moriDeclarationFactors': null,
      'lastMatchPointSummary': null,
      'lastDrawerId': null,
      'lastPlayerId': null,
      'isDrawCompetitive': false,
      'deckResetAt': null,
    });
  }

  /// シリーズ対戦の次の1戦を、ロビー経由せず1回の更新で開始する
  Future<void> startSeriesNextMatch({
    required List<String> players,
    required Map<String, List<Map<String, dynamic>>> playerCards,
    required Map<String, int> playerHands,
    required List<Map<String, dynamic>> deck,
    required Map<String, dynamic> field,
    required List<Map<String, dynamic>> fieldHistory,
  }) async {
    await _roomRef.update({
      'players': players,
      'playerCards': playerCards,
      'playerHands': playerHands,
      'deck': deck,
      'deckIndex': deck,
      'field': field,
      'fieldHistory': fieldHistory,
      'isInitialPhase': true,
      'currentTurnIndex': 0,
      'gameStarted': true,
      'roomStatus': 'closed',
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
      'moriGaeshiCount': null,
      'moriDeclarationFactors': null,
      'lastMatchPointSummary': null,
      'lastDrawerId': null,
      'lastPlayerId': 'system',
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
      'moriGaeshiCount': null,
      'moriDeclarationFactors': null,
      'lastMatchPointSummary': null,
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

  // --- 追加：ホスト不在や古いルームの一括クリーンアップ処理 ---
  // インスタンス化せずに呼べるように static メソッドとして定義します
  static Future<void> cleanupOldRooms() async {
    final ref = FirebaseDatabase.instance.ref('rooms');
    final snapshot = await ref.get();
    
    if (!snapshot.exists || snapshot.value == null) return;

    final rooms = snapshot.value as Map;
    final now = DateTime.now().millisecondsSinceEpoch;
    
    // 24時間（ミリ秒）
    const int twentyFourHours = 24 * 60 * 60 * 1000;

    rooms.forEach((key, value) {
      if (value is! Map) return;

      String status = value['roomStatus'] ?? 'open';
      List? players = value['players'] as List?;
      int createdAt = value['createdAt'] ?? now; // createdAtがない古い部屋は一旦現在の時間扱いに

      // 削除条件の判定
      bool isClosed = (status == 'closed');
      bool isEmpty = (players == null || players.isEmpty);
      bool isTooOld = (now - createdAt > twentyFourHours);

      if (isClosed || isEmpty || isTooOld) {
        // 条件に合致した部屋（ノード）を削除
        FirebaseDatabase.instance.ref('rooms/$key').remove();
        print('クリーンアップ: ルーム $key を削除しました');
      }
    });
  }
}