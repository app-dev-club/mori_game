import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/features/game/game_board_view.dart';
import 'package:mori_game/logic/game_rules.dart';

void main() {
  const heart7 = CardWidget(number: 7, suit: Suit.heart);
  const spade7 = CardWidget(number: 7, suit: Suit.spade);
  const heart5 = CardWidget(number: 5, suit: Suit.heart);
  const joker = CardWidget(number: 0, suit: Suit.joker);

  group('canPlayNormal', () {
    test('山札をめくる前は手札から出せない', () {
      expect(
        GameRules.canPlayNormal(-1, Suit.joker, heart7),
        isFalse,
      );
    });

    test('初期フェーズは同じ数字のみ出せる', () {
      expect(
        GameRules.canPlayNormal(7, Suit.heart, spade7, isInitialPhase: true),
        isTrue,
      );
      expect(
        GameRules.canPlayNormal(7, Suit.heart, heart5, isInitialPhase: true),
        isFalse,
      );
    });

    test('通常フェーズは同じ数字または同じスートで出せる', () {
      expect(GameRules.canPlayNormal(7, Suit.heart, spade7), isTrue);
      expect(GameRules.canPlayNormal(7, Suit.heart, heart5), isTrue);
      expect(GameRules.canPlayNormal(7, Suit.heart, CardWidget(number: 5, suit: Suit.spade)), isFalse);
    });

    test('ジョーカー場では任意のカードを出せる', () {
      expect(GameRules.canPlayNormal(0, Suit.joker, heart5), isTrue);
      expect(GameRules.canPlayNormal(0, Suit.joker, heart5, isInitialPhase: true), isTrue);
    });

    test('未めくりプレースホルダーはジョーカー場とみなさない', () {
      expect(GameRules.isJokerOnField(-1, Suit.joker), isFalse);
      expect(GameRules.isJokerOnField(0, Suit.joker), isTrue);
    });
  });
}
