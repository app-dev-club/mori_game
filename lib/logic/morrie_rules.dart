import 'bot_logic.dart';

/// 架空通貨モリーの賭けルール
class MorrieRules {
  static const int defaultStartingBalance = 10;
  static const int botFixedBalance = 5;
  static const int adRewardAmount = 5;

  static int morrieDeltaForPoints(int points, int rate) => points * rate;

  /// もり成立時のモリー移動量（ポイント × レート）
  static int moriMorrieAmount(int pointDelta, int rate) {
    if (pointDelta <= 0 || rate <= 0) return 0;
    return pointDelta * rate;
  }

  /// もり成立時: 最後にもりを宣言された側 → 宣言者へモリー移動
  static MoriMorrieTransfer computeMoriMorrieTransfer({
    required int pointDelta,
    required int rate,
    required String winnerId,
    required String loserId,
    required Map<String, int> humanBalances,
  }) {
    final requested = moriMorrieAmount(pointDelta, rate);
    if (requested <= 0) {
      return const MoriMorrieTransfer(
        requestedMorrie: 0,
        actualMorrie: 0,
        morrieBurst: false,
        deltas: {},
      );
    }

    final loserAvailable = BotLogic.isBot(loserId)
        ? botFixedBalance
        : (humanBalances[loserId] ?? 0).clamp(0, 1 << 30);
    final actual = requested < loserAvailable ? requested : loserAvailable;
    final morrieBurst =
        !BotLogic.isBot(loserId) && requested > loserAvailable;

    final deltas = <String, int>{};
    if (!BotLogic.isBot(loserId)) {
      deltas[loserId] = -actual;
    }
    if (!BotLogic.isBot(winnerId)) {
      deltas[winnerId] = (deltas[winnerId] ?? 0) + actual;
    }

    return MoriMorrieTransfer(
      requestedMorrie: requested,
      actualMorrie: actual,
      morrieBurst: morrieBurst,
      deltas: deltas,
    );
  }

  static String describeMoriMorrieTransfer({
    required String winnerName,
    required String loserName,
    required int pointDelta,
    required int rate,
    required MoriMorrieTransfer transfer,
  }) {
    if (transfer.actualMorrie <= 0) return '';
    final lines = <String>[
      'モリー: $loserName → $winnerName ${transfer.actualMorrie}（$pointDelta点×$rate）',
    ];
    if (transfer.morrieBurst) {
      lines.add('$loserName は所持モリー不足のため全財産を失い、飛びとなりました');
    }
    return lines.join('\n');
  }

  static Map<String, int> botBalancesAfterSettlement(
    Iterable<String> participantIds,
  ) {
    return {
      for (final id in participantIds)
        if (BotLogic.isBot(id)) id: botFixedBalance,
    };
  }
}

class MoriMorrieTransfer {
  final int requestedMorrie;
  final int actualMorrie;
  final bool morrieBurst;
  final Map<String, int> deltas;

  const MoriMorrieTransfer({
    required this.requestedMorrie,
    required this.actualMorrie,
    required this.morrieBurst,
    required this.deltas,
  });
}
