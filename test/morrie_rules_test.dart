import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/morrie_rules.dart';

void main() {
  group('MorrieRules', () {
    test('もり成立時のモリー移動量はポイント×レート', () {
      expect(MorrieRules.moriMorrieAmount(12, 5), 60);
      expect(MorrieRules.moriMorrieAmount(0, 5), 0);
    });

    test('loser → winner へ指定分モリーが動く', () {
      final transfer = MorrieRules.computeMoriMorrieTransfer(
        pointDelta: 6,
        rate: 2,
        winnerId: 'winner',
        loserId: 'loser',
        playerBalances: const {'winner': 100, 'loser': 50},
      );

      expect(transfer.requestedMorrie, 12);
      expect(transfer.actualMorrie, 12);
      expect(transfer.morrieBurst, isFalse);
      expect(transfer.deltas['loser'], -12);
      expect(transfer.deltas['winner'], 12);
    });

    test('所持モリー不足なら全財産移動して飛び', () {
      final transfer = MorrieRules.computeMoriMorrieTransfer(
        pointDelta: 10,
        rate: 5,
        winnerId: 'winner',
        loserId: 'loser',
        playerBalances: const {'winner': 100, 'loser': 3},
      );

      expect(transfer.requestedMorrie, 50);
      expect(transfer.actualMorrie, 3);
      expect(transfer.morrieBurst, isTrue);
      expect(transfer.deltas['loser'], -3);
      expect(transfer.deltas['winner'], 3);
    });

    test('Botもモリー増減の対象になる', () {
      final transfer = MorrieRules.computeMoriMorrieTransfer(
        pointDelta: 5,
        rate: 1,
        winnerId: 'human',
        loserId: 'bot_1',
        playerBalances: const {'human': 100, 'bot_1': 8},
      );

      expect(transfer.deltas['bot_1'], -5);
      expect(transfer.deltas['human'], 5);
      expect(transfer.morrieBurst, isFalse);
    });

    test('Bot所持不足でも飛びになる', () {
      final transfer = MorrieRules.computeMoriMorrieTransfer(
        pointDelta: 10,
        rate: 2,
        winnerId: 'human',
        loserId: 'bot_1',
        playerBalances: const {'human': 100, 'bot_1': 3},
      );

      expect(transfer.actualMorrie, 3);
      expect(transfer.morrieBurst, isTrue);
    });

    test('もり成立時に払い切って0でも飛び', () {
      final transfer = MorrieRules.computeMoriMorrieTransfer(
        pointDelta: 6,
        rate: 2,
        winnerId: 'winner',
        loserId: 'loser',
        playerBalances: const {'winner': 100, 'loser': 12},
      );

      expect(transfer.requestedMorrie, 12);
      expect(transfer.actualMorrie, 12);
      expect(transfer.morrieBurst, isTrue);
      expect(transfer.deltas['loser'], -12);
      expect(transfer.deltas['winner'], 12);
    });

    test('もともと0でモリー移動なしの場合は飛びにならない', () {
      final transfer = MorrieRules.computeMoriMorrieTransfer(
        pointDelta: 6,
        rate: 2,
        winnerId: 'winner',
        loserId: 'loser',
        playerBalances: const {'winner': 100, 'loser': 0},
      );

      expect(transfer.actualMorrie, 0);
      expect(transfer.morrieBurst, isFalse);
      expect(transfer.deltas['loser'], 0);
      expect(transfer.deltas['winner'], 0);
    });

    test('Bot勝利時もBot側にdeltaが入る', () {
      final transfer = MorrieRules.computeMoriMorrieTransfer(
        pointDelta: 4,
        rate: 2,
        winnerId: 'bot_1',
        loserId: 'human',
        playerBalances: const {'human': 20, 'bot_1': 5},
      );

      expect(transfer.deltas['human'], -8);
      expect(transfer.deltas['bot_1'], 8);
    });

    test('initialBotBalances', () {
      expect(
        MorrieRules.initialBotBalances(const ['bot_1']),
        {'bot_1': MorrieRules.botFixedBalance},
      );
    });

    test('バースト時は2点×レート分だけ減る', () {
      expect(MorrieRules.burstMorrieAmount(5), 10);

      final deduction = MorrieRules.computeBurstMorrieDeduction(
        rate: 3,
        burstPlayerId: 'player',
        playerBalances: const {'player': 20},
      );

      expect(deduction.requestedMorrie, 6);
      expect(deduction.actualMorrie, 6);
      expect(deduction.morrieBurst, isFalse);
      expect(deduction.deltas['player'], -6);
    });

    test('バースト時Botも減算対象', () {
      final deduction = MorrieRules.computeBurstMorrieDeduction(
        rate: 2,
        burstPlayerId: 'bot_1',
        playerBalances: const {'bot_1': 5},
      );

      expect(deduction.actualMorrie, 4);
      expect(deduction.morrieBurst, isFalse);
      expect(deduction.deltas['bot_1'], -4);
    });

    test('バースト時に払い切って0でも飛び', () {
      final deduction = MorrieRules.computeBurstMorrieDeduction(
        rate: 2,
        burstPlayerId: 'player',
        playerBalances: const {'player': 4},
      );

      expect(deduction.requestedMorrie, 4);
      expect(deduction.actualMorrie, 4);
      expect(deduction.morrieBurst, isTrue);
      expect(deduction.deltas['player'], -4);
    });

    test('バースト時所持不足なら全財産を失い飛び', () {
      final deduction = MorrieRules.computeBurstMorrieDeduction(
        rate: 5,
        burstPlayerId: 'player',
        playerBalances: const {'player': 3},
      );

      expect(deduction.requestedMorrie, 10);
      expect(deduction.actualMorrie, 3);
      expect(deduction.morrieBurst, isTrue);
      expect(deduction.deltas['player'], -3);
    });

    test('バースト時所持0でも飛び', () {
      final deduction = MorrieRules.computeBurstMorrieDeduction(
        rate: 3,
        burstPlayerId: 'bot_1',
        playerBalances: const {'bot_1': 0},
      );

      expect(deduction.actualMorrie, 0);
      expect(deduction.morrieBurst, isTrue);
      expect(deduction.deltas['bot_1'], 0);
    });
  });
}
