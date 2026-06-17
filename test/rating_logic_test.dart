import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/rating_logic.dart';

void main() {
  group('RatingLogic', () {
    test('rankByPoints はポイント降順に順位付けする', () {
      final ranked = RatingLogic.rankByPoints(
        ['a', 'b', 'c'],
        {'a': 10, 'b': 10, 'c': 5},
      );
      expect(ranked[0].id, 'a');
      expect(ranked[0].rank, 1);
      expect(ranked[1].id, 'b');
      expect(ranked[1].rank, 1);
      expect(ranked[2].id, 'c');
      expect(ranked[2].rank, 3);
    });

    test('同レート2人で勝者はプラス・敗者はマイナス', () {
      const rating = 1500;
      final deltas = RatingLogic.computeDeltas(
        {'a': rating, 'b': rating},
        ['a', 'b'],
        {'a': 10, 'b': -10},
      );
      expect(deltas['a'], greaterThan(0));
      expect(deltas['b'], lessThan(0));
      expect(deltas['a']! + deltas['b']!, 0);
    });

    test('buildSeriesSummary に順位とレート変動を含める', () {
      final summary = RatingLogic.buildSeriesSummary(
        ranked: [
          (id: 'a', points: 10, rank: 1),
          (id: 'b', points: -10, rank: 2),
        ],
        oldRatings: {'a': 1500, 'b': 1500},
        deltas: {'a': 16, 'b': -16},
        displayNames: {'a': 'Alice', 'b': 'Bot 1'},
      );
      expect(summary, contains('1位 Alice'));
      expect(summary, contains('Bot 1'));
      expect(summary, contains('+16'));
      expect(summary, contains('-16'));
    });
  });
}
