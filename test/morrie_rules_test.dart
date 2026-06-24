import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/morrie_rules.dart';

void main() {
  group('MorrieRules', () {
    test('ポイント×レートでモリー変動を計算する', () {
      expect(MorrieRules.morrieDeltaForPoints(12, 5), 60);
      expect(MorrieRules.morrieDeltaForPoints(-3, 10), -30);
    });

    test('Bot敗北時は5モリーを上限に人間への支払いを調整する', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['human', 'bot_1'],
        finalPoints: const {'human': 10, 'bot_1': -10},
        rate: 5,
      );

      expect(updates['human'], 5);
      expect(updates.containsKey('bot_1'), isFalse);
    });

    test('Bot勝利時は人間の負け分をそのまま適用する', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['human', 'bot_1'],
        finalPoints: const {'human': -8, 'bot_1': 8},
        rate: 2,
      );

      expect(updates['human'], -16);
    });

    test('試合後のBot残高は常に5に戻す', () {
      expect(
        MorrieRules.botBalancesAfterSettlement(const ['bot_1', 'human']),
        {'bot_1': MorrieRules.botFixedBalance},
      );
    });
  });
}
