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