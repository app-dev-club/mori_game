import '../features/game/game_board_view.dart';

class GameRules {
  static bool isBurst(int handCount) => handCount >= 7;

  static bool isValidMori(int fieldNumber, List<CardWidget> selectedCards) {
    if (fieldNumber == -1 || selectedCards.isEmpty) return false;
    if (selectedCards.length == 1) return selectedCards[0].number == fieldNumber;
    if (selectedCards.length == 2) {
      int a = selectedCards[0].number;
      int b = selectedCards[1].number;
      return (a + b == fieldNumber) || (a - b == fieldNumber) || (b - a == fieldNumber) ||
             (a * b == fieldNumber) || (a != 0 && b % a == 0 && a ~/ b == fieldNumber) ||
             (b != 0 && a % b == 0 && a ~/ b == fieldNumber);
    }
    int sum = selectedCards.fold(0, (prev, card) => prev + card.number);
    return sum == fieldNumber;
  }

  static bool canPlayNormal(int fieldNumber, Suit fieldSuit, CardWidget card) {
    if (fieldNumber == -1) return true;
    return card.number == fieldNumber || card.suit == fieldSuit;
  }
}