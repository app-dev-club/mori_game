import 'package:mori_game/models/CardModel.dart'; 

class MoriLogic {
  // 通常の「もり」判定（合計値）
  static bool checkNormalMori(int fieldNum, List<CardModel> hand) {
    final validCards = hand.where((c) => c.suit != Suit.joker).toList();
    if (validCards.isEmpty) return false;
    
    int sum = validCards.fold(0, (prev, c) => prev + c.number);
    return sum == fieldNum;
  }

  // 特殊ルール（2枚時の四則演算）
  static bool checkSpecialMori(int fieldNum, List<CardModel> hand) {
    final validCards = hand.where((c) => c.suit != Suit.joker).toList();
    if (validCards.length != 2) return false;

    int a = validCards[0].number;
    int b = validCards[1].number;

    return (a + b == fieldNum) ||
           (a - b == fieldNum) ||
           (b - a == fieldNum) ||
           (a * b == fieldNum) ||
           (b != 0 && a % b == 0 && a ~/ b == fieldNum) ||
           (a != 0 && b % a == 0 && b ~/ a == fieldNum);
  }
}