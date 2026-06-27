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
        humanBalances: const {'winner': 100, 'loser': 50},
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
        humanBalances: const {'winner': 100, 'loser': 3},
      );

      expect(transfer.requestedMorrie, 50);
      expect(transfer.actualMorrie, 3);
      expect(transfer.morrieBurst, isTrue);
      expect(transfer.deltas['loser'], -3);
      expect(transfer.deltas['winner'], 3);
    });

    test('Bot敗北時は5モリーまで', () {
      final transfer = MorrieRules.computeMoriMorrieTransfer(
        pointDelta: 10,
        rate: 5,
        winnerId: 'human',
        loserId: 'bot_1',
        humanBalances: const {'human': 100},
      );

      expect(transfer.actualMorrie, 5);
      expect(transfer.morrieBurst, isFalse);
      expect(transfer.deltas['human'], 5);
      expect(transfer.deltas.containsKey('bot_1'), isFalse);
    });

    test('試合後のBot残高は常に5に戻す', () {
      expect(
        MorrieRules.botBalancesAfterSettlement(const ['bot_1', 'human']),
        {'bot_1': MorrieRules.botFixedBalance},
      );
    });
  });
}
