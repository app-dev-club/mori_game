import 'bot_logic.dart';

/// 架空通貨モリーの賭けルール
class MorrieRules {
  static const int defaultStartingBalance = 10;
  static const int botFixedBalance = 5;
  static const int adRewardAmount = 5;

  static int morrieDeltaForPoints(int points, int rate) => points * rate;

  static Map<String, int> rawMorrieDeltas(
    Map<String, int> finalPoints,
    int rate,
  ) {
    return {
      for (final entry in finalPoints.entries)
        entry.key: morrieDeltaForPoints(entry.value, rate),
    };
  }

  /// 人間プレイヤーへの残高変動を計算する（累計得点 × レート）。
  static Map<String, int> humanBalanceUpdates({
    required Iterable<String> participantIds,
    required Map<String, int> finalPoints,
    required int rate,
  }) {
    final raw = rawMorrieDeltas(finalPoints, rate);
    return {
      for (final id in participantIds)
        if (!BotLogic.isBot(id)) id: raw[id] ?? 0,
    };
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
