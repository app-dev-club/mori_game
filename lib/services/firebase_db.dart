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

  Future<void> setupRoom(String myId, List<CardWidget> deck, bool isPrivate) async {
    await _roomRef.set({
      'host': myId,
      'players': [myId],
      'playerHands': {myId: 5},
      'deck': deck.map((c) => {'number': c.number, 'suit': c.suit.name}).toList(),
      'field': {'number': -1, 'suit': 'joker'},
      'isInitialPhase': true,
      'currentTurnIndex': 0,
      'isDrawCompetitive': false,
      'gameStarted': false,
      'isPrivate': isPrivate,
      'roomStatus': 'open',
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

  Future<void> setRematchReady(String playerId) =>
      _roomRef.child('rematchReady/$playerId').set(true);

  /// 全員の準備が揃ったらホストが呼び、同じメンバーでゲームを初期化する。
  Future<void> restartGame({
    required List<String> players,
    required Map<String, List<Map<String, dynamic>>> rematchHands,
    required List<Map<String, dynamic>> remainingDeck,
    required int rematchGeneration,
  }) async {
    await _roomRef.update({
      'players': players,
      'playerHands': {for (final p in players) p: 5},
      'deck': remainingDeck,
      'rematchHands': rematchHands,
      'rematchGeneration': rematchGeneration,
      'field': {'number': -1, 'suit': 'joker'},
      'isInitialPhase': true,
      'currentTurnIndex': 0,
      'gameStarted': true,
      'moriPhase': 'none',
      'lastMoriPlayerId': null,
      'loserPlayerId': null,
      'moriRevealedHand': null,
      'moriRevealedType': null,
      'burstPlayerId': null,
      'lastDrawerId': null,
      'lastPlayerId': null,
      'isDrawCompetitive': false,
      'rematchReady': null,
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