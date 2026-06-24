import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/morrie_rules.dart';

void main() {
  group('MorrieRules', () {
    test('ポイント×レートでモリー変動を計算する', () {
      expect(MorrieRules.morrieDeltaForPoints(12, 5), 60);
      expect(MorrieRules.morrieDeltaForPoints(-3, 10), -30);
    });

    test('所持以上の負けは所持分だけ徴収し勝者に渡す', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['winner', 'loser'],
        finalPoints: const {'winner': 12, 'loser': -12},
        rate: 2,
        humanBalances: const {'winner': 100, 'loser': 3},
      );

      expect(updates['loser'], -3);
      expect(updates['winner'], 3);
    });

    test('複数勝者はポイント比率で整数山分けする', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['a', 'b', 'loser'],
        finalPoints: const {'a': 6, 'b': 6, 'loser': -12},
        rate: 1,
        humanBalances: const {'a': 10, 'b': 10, 'loser': 10},
      );

      expect(updates['loser'], -10);
      expect(updates['a'], 5);
      expect(updates['b'], 5);
    });

    test('端数は余りの大きい勝者に配る', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['a', 'b', 'loser'],
        finalPoints: const {'a': 1, 'b': 1, 'loser': -2},
        rate: 1,
        humanBalances: const {'a': 10, 'b': 10, 'loser': 3},
      );

      expect(updates['loser'], -2);
      expect(updates['a']! + updates['b']!, 2);
      expect(updates.values.fold<int>(0, (sum, v) => sum + v), 0);
    });

    test('Bot敗北時は5モリーを上限に人間へ配分する', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['human', 'bot_1'],
        finalPoints: const {'human': 10, 'bot_1': -10},
        rate: 5,
        humanBalances: const {'human': 100},
      );

      expect(updates['human'], 5);
      expect(updates.containsKey('bot_1'), isFalse);
    });

    test('Bot勝利時は人間の負け分を所持上限まで徴収する', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['human', 'bot_1'],
        finalPoints: const {'human': -8, 'bot_1': 8},
        rate: 2,
        humanBalances: const {'human': 10},
      );

      expect(updates['human'], -10);
      expect(updates.containsKey('bot_1'), isFalse);
    });

    test('Botと人間が同率勝利でも人間だけが配分を受け取る', () {
      final updates = MorrieRules.humanBalanceUpdates(
        participantIds: const ['human', 'bot_1', 'loser'],
        finalPoints: const {'human': 5, 'bot_1': 5, 'loser': -10},
        rate: 1,
        humanBalances: const {'human': 100, 'loser': 10},
      );

      expect(updates['loser'], -10);
      expect(updates['human'], 5);
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
