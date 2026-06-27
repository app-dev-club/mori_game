import 'bot_logic.dart';

/// 架空通貨モリーの賭けルール
class MorrieRules {
  static const int defaultStartingBalance = 10;
  static const int botFixedBalance = 5;
  static const int adRewardAmount = 5;
  static const int burstRecoveryAmount = 5;

  static int morrieDeltaForPoints(int points, int rate) => points * rate;

  static int resolvePlayerBalance(
    String playerId,
    Map<String, int> playerBalances,
  ) {
    if (BotLogic.isBot(playerId)) {
      return (playerBalances[playerId] ?? botFixedBalance).clamp(0, 1 << 30);
    }
    return (playerBalances[playerId] ?? defaultStartingBalance).clamp(0, 1 << 30);
  }

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
    required Map<String, int> playerBalances,
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

    final loserAvailable = resolvePlayerBalance(loserId, playerBalances);
    final actual = requested < loserAvailable ? requested : loserAvailable;
    final morrieBurst = requested > loserAvailable;

    return MoriMorrieTransfer(
      requestedMorrie: requested,
      actualMorrie: actual,
      morrieBurst: morrieBurst,
      deltas: {
        loserId: -actual,
        winnerId: actual,
      },
    );
  }

  static String describeMoriMorrieTransfer({
    required String winnerName,
    required String loserName,
    required String loserId,
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
      if (BotLogic.isBot(loserId)) {
        lines.add('（試合終了後に$burstRecoveryAmountモリーが付与されます）');
      }
    }
    return lines.join('\n');
  }

  static Map<String, int> initialBotBalances(Iterable<String> botIds) {
    return {for (final id in botIds) id: botFixedBalance};
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
