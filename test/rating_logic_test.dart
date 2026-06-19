import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/open_skill.dart';
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

    test('同スキル2人で勝者はプラス・敗者はマイナス', () {
      final skill = OpenSkillConstants.defaultRating();
      final updates = RatingLogic.computeSkillUpdates(
        oldRatings: {'a': skill, 'b': skill},
        playerIds: ['a', 'b'],
        finalPoints: {'a': 10, 'b': -10},
      );
      expect(updates['a']!.ratingDelta, greaterThan(0));
      expect(updates['b']!.ratingDelta, lessThan(0));
      expect(updates['a']!.newRating.sigma, lessThan(skill.sigma));
    });

    test('buildSeriesSummary に順位とレート変動を含める', () {
      final old = OpenSkillConstants.defaultRating();
      final summary = RatingLogic.buildSeriesSummary(
        ranked: [
          (id: 'a', points: 10, rank: 1),
          (id: 'b', points: -10, rank: 2),
        ],
        oldRatings: {'a': old, 'b': old},
        updates: {
          'a': (oldRating: old, newRating: old.copyWith(mu: old.mu + 2), ratingDelta: 2),
          'b': (oldRating: old, newRating: old.copyWith(mu: old.mu - 2), ratingDelta: -2),
        },
        displayNames: {'a': 'Alice', 'b': 'Bot 1'},
      );
      expect(summary, contains('1位 Alice'));
      expect(summary, contains('Bot 1'));
      expect(summary, contains('σ'));
    });
  });
}
