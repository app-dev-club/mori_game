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
  });
}
