import '../features/game/game_board_view.dart';

class GameRules {
  /// バースト判定（手札が7枚以上で負け）
  static bool isBurst(int handCount) => handCount >= 7;

  /// もり判定ロジック
  /// [fieldNumber]: 場の数字
  /// [selectedCards]: 選択されたカードリスト
  static bool isValidMori(int fieldNumber, List<CardWidget> selectedCards) {
    if (fieldNumber == -1 || selectedCards.isEmpty) return false;

    // 1枚の場合：数字が一致
    if (selectedCards.length == 1) {
      return selectedCards[0].number == fieldNumber;
    }
    
    // 2枚の場合：四則演算
    if (selectedCards.length == 2) {
      int a = selectedCards[0].number;
      int b = selectedCards[1].number;
      return (a + b == fieldNumber) ||
             (a - b == fieldNumber) ||
             (b - a == fieldNumber) ||
             (a * b == fieldNumber) ||
             (a != 0 && b % a == 0 && a ~/ b == fieldNumber) ||
             (b != 0 && a % b == 0 && a ~/ b == fieldNumber);
    }

    // 3枚以上の全体合計（和）
    int sum = selectedCards.fold(0, (prev, card) => prev + card.number);
    return sum == fieldNumber;
  }

  /// 通常プレイ（ターン時）の判定：同じスート or 同じ数字
  static bool canPlayNormal(int fieldNumber, Suit fieldSuit, CardWidget card) {
    if (fieldNumber == -1) return true;
    return card.number == fieldNumber || card.suit == fieldSuit;
  }
}