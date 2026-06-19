import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/open_skill.dart';

void main() {
  group('OpenSkill', () {
    test('初期レートは ordinal 0 → 表示 1500', () {
      final skill = OpenSkillConstants.defaultRating();
      expect(OpenSkill.ordinal(skill), closeTo(0, 0.001));
      expect(OpenSkill.displayRating(skill), 1500);
    });

    test('2人対戦で勝者の μ が上がり敗者の μ が下がる', () {
      final a = OpenSkillConstants.defaultRating();
      final b = OpenSkillConstants.defaultRating();
      final result = OpenSkill.rate([
        [a],
        [b],
      ], [1, 2]);
      expect(result[0].first.mu, greaterThan(a.mu));
      expect(result[1].first.mu, lessThan(b.mu));
    });

    test('legacy レート 1600 は μ を移行できる', () {
      final skill = OpenSkill.fromLegacyRating(1600);
      expect(OpenSkill.displayRating(skill), 1600);
    });
  });
}
