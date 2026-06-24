import 'bot_logic.dart';

/// 架空通貨モリーの賭けルール
class MorrieRules {
  static const int defaultStartingBalance = 10;
  static const int botFixedBalance = 5;

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

  /// 人間プレイヤーへの残高変動を計算する。
  /// Bot が勝った場合は人間の負け分をそのまま適用し、Bot の勝ち分は持ち越さない。
  /// Bot が負けた場合は Bot の持ち分（5モリー）を上限として人間への支払いを調整する。
  static Map<String, int> humanBalanceUpdates({
    required Iterable<String> participantIds,
    required Map<String, int> finalPoints,
    required int rate,
  }) {
    final raw = rawMorrieDeltas(finalPoints, rate);
    final updates = <String, int>{
      for (final id in participantIds)
        if (!BotLogic.isBot(id)) id: raw[id] ?? 0,
    };

    for (final id in participantIds) {
      if (!BotLogic.isBot(id)) continue;
      final botDelta = raw[id] ?? 0;
      if (botDelta >= 0) continue;

      final requestedPayout = -botDelta;
      if (requestedPayout <= botFixedBalance) continue;

      final winners = updates.entries.where((e) => e.value > 0).toList();
      if (winners.isEmpty) continue;

      final scale = botFixedBalance / requestedPayout;
      for (final winner in winners) {
        updates[winner.key] = (winner.value * scale).round();
      }
    }

    return updates;
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
