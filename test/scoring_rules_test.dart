import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/features/game/game_board_view.dart';
import 'package:mori_game/logic/scoring_rules.dart';

CardWidget card(int n, [Suit s = Suit.spade]) => CardWidget(number: n, suit: s);

void main() {
  group('handFactor', () {
    test('1枚・ジョーカーなしは3', () {
      expect(ScoringRules.handFactor([card(5)]), 3);
    });

    test('1枚・ジョーカーのみは3ではない', () {
      expect(ScoringRules.handFactor([card(0, Suit.joker)]), 1);
    });

    test('2枚は1', () {
      expect(ScoringRules.handFactor([card(2), card(3)]), 1);
    });

    test('ジョーカー+1枚は1', () {
      expect(ScoringRules.handFactor([card(0, Suit.joker), card(4)]), 1);
    });

    test('ジョーカー+1枚・オープンジョーカーは3', () {
      expect(
        ScoringRules.handFactor([card(0, Suit.joker), card(4)], openJoker: true),
        3,
      );
    });

    test('ジョーカーのみ・オープンジョーカーでも1', () {
      expect(
        ScoringRules.handFactor([card(0, Suit.joker)], openJoker: true),
        1,
      );
    });

    test('ジョーカー2枚+通常2枚は2枚もりとして係数1', () {
      expect(
        ScoringRules.handFactor([
          card(0, Suit.joker),
          card(0, Suit.joker),
          card(2),
          card(3),
        ]),
        1,
      );
    });

    test('ジョーカー+通常3枚は3枚もりとして係数1', () {
      expect(
        ScoringRules.handFactor([
          card(0, Suit.joker),
          card(2),
          card(3),
          card(4),
        ]),
        1,
      );
    });

    test('4枚は2', () {
      expect(
        ScoringRules.handFactor([card(1), card(2), card(3), card(4)]),
        2,
      );
    });

    test('5枚は5', () {
      expect(
        ScoringRules.handFactor([
          card(1),
          card(2),
          card(3),
          card(4),
          card(5),
        ]),
        5,
      );
    });
  });

  group('moriGaeshiMultiplier', () {
    test('もり返しなしは×1', () {
      expect(ScoringRules.moriGaeshiMultiplier(0), 1);
    });

    test('もり返し1回は×2', () {
      expect(ScoringRules.moriGaeshiMultiplier(1), 2);
    });

    test('もり返し2回は×4', () {
      expect(ScoringRules.moriGaeshiMultiplier(2), 4);
    });
  });

  group('moriWinnerDelta', () {
    test('1枚もりのみは3点', () {
      expect(ScoringRules.moriWinnerDelta([3], 0), 3);
    });

    test('2枚もり＋1枚もり返しは1×3×2=6点', () {
      expect(ScoringRules.moriWinnerDelta([1, 3], 1), 6);
    });

    test('1枚もり＋1枚もり返しは3×3×2=18点', () {
      expect(ScoringRules.moriWinnerDelta([3, 3], 1), 18);
    });

    test('もり返し2回は最後に×4', () {
      expect(ScoringRules.moriWinnerDelta([3, 1, 3], 2), 36);
    });
  });
}
