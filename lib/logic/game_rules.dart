import '../features/game/game_board_view.dart';

class GameRules {
  static const int maxHandSize = 7;

  /// バースト判定
  static bool isBurst(int handCount, bool canPlayDrawnCard) {
    return handCount >= maxHandSize && !canPlayDrawnCard;
  }

  /// ターン中にドロー可能か（1ターン1回・手札上限7枚）
  static bool canDraw(int handCount, String? lastDrawerId, String myId) {
    return handCount < maxHandSize && lastDrawerId != myId;
  }

  /// ドロー競合フェーズ（手札6枚以下でドロー後）が有効か
  static bool isDrawCompetitivePhase(bool isDrawCompetitive, String? lastDrawerId) {
    return isDrawCompetitive && lastDrawerId != null;
  }

  /// ドローした直後の「次のプレイヤー」か
  static bool isPlayerAfterDrawer(String? lastDrawerId, List<String> players, String myId) {
    if (lastDrawerId == null || players.isEmpty) return false;
    final drawerIdx = players.indexOf(lastDrawerId);
    if (drawerIdx < 0) return false;
    return players[(drawerIdx + 1) % players.length] == myId;
  }

  /// ドロー競合中にカードを出せるか（ドローした人 or 次のプレイヤー）
  static bool canPlayInDrawCompetition({
    required bool isDrawCompetitive,
    required String? lastDrawerId,
    required List<String> players,
    required String myId,
  }) {
    if (!isDrawCompetitivePhase(isDrawCompetitive, lastDrawerId)) return false;
    return lastDrawerId == myId || isPlayerAfterDrawer(lastDrawerId, players, myId);
  }

  /// ドロー競合中に山札から引けるか
  static bool canDrawInCompetition({
    required bool isDrawCompetitive,
    required String? lastDrawerId,
    required List<String> players,
    required String myId,
    required int handCount,
  }) {
    if (!isDrawCompetitivePhase(isDrawCompetitive, lastDrawerId)) return false;
    if (!isPlayerAfterDrawer(lastDrawerId, players, myId)) return false;
    return canDraw(handCount, lastDrawerId, myId);
  }

  /// もり判定ロジック（手札全体で計算、JQK対応、ジョーカー除外）
  static bool isValidMori(int fieldNumber, List<CardWidget> hand) {
    if (fieldNumber == -1 || hand.isEmpty) return false;

    // ジョーカーを除外したリストを作成（枚数カウント除外ルール）
    final numbers = hand
        .where((c) => c.suit != Suit.joker)
        .map((c) => c.number)
        .toList();
    
    int effectiveCount = numbers.length;

    // 手札が1枚の場合
    if (effectiveCount == 1) {
      return numbers[0] == fieldNumber;
    }
    
    // 手札が2枚の場合（四則演算）
    if (effectiveCount == 2) {
      int a = numbers[0];
      int b = numbers[1];
      return (a + b == fieldNumber) ||
             (a - b == fieldNumber) || (b - a == fieldNumber) ||
             (a * b == fieldNumber) ||
             (b != 0 && a % b == 0 && a ~/ b == fieldNumber) ||
             (a != 0 && b % a == 0 && b ~/ a == fieldNumber);
    }

    // 手札が3枚以上の場合（すべての和）
    if (effectiveCount >= 3) {
      int sum = numbers.fold(0, (prev, n) => prev + n);
      return sum == fieldNumber;
    }

    return false;
  }

  /// 通常プレイ判定
  static bool canPlayNormal(int fieldNumber, Suit fieldSuit, CardWidget card) {
    if (fieldNumber == -1) return true; // 初期状態
    if (fieldSuit == Suit.joker) return true; // ジョーカー場
    return card.number == fieldNumber || card.suit == fieldSuit;
  }
}