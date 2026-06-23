import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/effects/game_effects.dart';
import 'package:mori_game/features/game/game_board_view.dart';

void main() {
  group('GameEffects', () {
    test('単騎もりはジョーカー以外が1枚', () {
      expect(
        GameEffects.isTankimoriHand([
          const CardWidget(number: 7, suit: Suit.heart),
        ]),
        isTrue,
      );
      expect(
        GameEffects.isTankimoriHand([
          const CardWidget(number: 0, suit: Suit.joker),
          const CardWidget(number: 7, suit: Suit.heart),
        ]),
        isTrue,
      );
      expect(
        GameEffects.isTankimoriHand([
          const CardWidget(number: 3, suit: Suit.spade),
          const CardWidget(number: 4, suit: Suit.club),
        ]),
        isFalse,
      );
    });
  });
}
