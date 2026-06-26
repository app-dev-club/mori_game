import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/morrie_rules.dart';

void main() {
  group('MorrieRules', () {
    test('ポイント×レートでモリー変動を計算する', () {
      expect(MorrieRules.morrieDeltaForPoints(12, 5), 60);
      expect(MorrieRules.morrieDeltaForPoints(-3, 10), -30);
    });

    test('人間プレイヤーは累計得点×レートをそのまま増減する', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['winner', 'loser'],
        finalPoints: const {'winner': 12, 'loser': -12},
        rate: 2,
      );

      expect(updates['winner'], 24);
      expect(updates['loser'], -24);
    });

    test('複数勝者もそれぞれ累計得点×レート', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['a', 'b', 'loser'],
        finalPoints: const {'a': 6, 'b': 6, 'loser': -12},
        rate: 3,
      );

      expect(updates['a'], 18);
      expect(updates['b'], 18);
      expect(updates['loser'], -36);
    });

    test('BotはhumanBalanceUpdatesに含めない', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['human', 'bot_1'],
        finalPoints: const {'human': 10, 'bot_1': -10},
        rate: 5,
      );

      expect(updates['human'], 50);
      expect(updates.containsKey('bot_1'), isFalse);
    });

    test('試合後のBot残高は常に5に戻す', () {
      expect(
        MorrieRules.botBalancesAfterSettlement(const ['bot_1', 'human']),
        {'bot_1': MorrieRules.botFixedBalance},
      );
    });
  });
}
