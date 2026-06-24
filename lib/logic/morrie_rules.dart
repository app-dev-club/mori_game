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

  /// 人間プレイヤーへの残高変動を計算する。
  ///
  /// - 所持モリーは 0 未満にならない（負け分は所持分まで）
  /// - 実際に徴収できた分だけを、勝者のポイント比率で整数配分する
  /// - Bot が勝った分は受け取らず、Bot が負けた分は [botFixedBalance] まで
  static Map<String, int> humanBalanceUpdates({
    required Iterable<String> participantIds,
    required Map<String, int> finalPoints,
    required int rate,
    required Map<String, int> humanBalances,
  }) {
    final ids = participantIds.toList();
    final raw = rawMorrieDeltas(finalPoints, rate);

    final winnerPoints = <String, int>{};
    var totalCollected = 0;

    final updates = <String, int>{
      for (final id in ids)
        if (!BotLogic.isBot(id)) id: 0,
    };

    for (final id in ids) {
      final points = finalPoints[id] ?? 0;
      final rawDelta = raw[id] ?? 0;
      if (points > 0) {
        winnerPoints[id] = points;
        continue;
      }
      if (rawDelta >= 0) continue;

      final requested = -rawDelta;
      final maxPay = BotLogic.isBot(id)
          ? botFixedBalance
          : (humanBalances[id] ?? 0).clamp(0, 1 << 30);
      final actual = requested < maxPay ? requested : maxPay;
      if (actual <= 0) continue;

      totalCollected += actual;
      if (!BotLogic.isBot(id)) {
        updates[id] = -actual;
      }
    }

    if (totalCollected <= 0 || winnerPoints.isEmpty) {
      return updates;
    }

    final gains = _splitIntegerByPoints(
      winnerPoints: winnerPoints,
      total: totalCollected,
      receives: (id) => !BotLogic.isBot(id),
    );
    for (final entry in gains.entries) {
      updates[entry.key] = (updates[entry.key] ?? 0) + entry.value;
    }

    return updates;
  }

  /// 勝者ポイント比率で整数配分する（端数は余りの大きい順に +1）
  static Map<String, int> _splitIntegerByPoints({
    required Map<String, int> winnerPoints,
    required int total,
    required bool Function(String id) receives,
  }) {
    if (total <= 0 || winnerPoints.isEmpty) return {};

    final totalPoints =
        winnerPoints.values.fold<int>(0, (sum, points) => sum + points);
    if (totalPoints <= 0) return {};

    final shares = <String, int>{};
    final fractionalParts = <String, double>{};
    var floorSum = 0;

    for (final entry in winnerPoints.entries) {
      if (entry.value <= 0) continue;
      final exact = total * entry.value / totalPoints;
      final base = exact.floor();
      floorSum += base;
      if (receives(entry.key)) {
        shares[entry.key] = base;
      }
      fractionalParts[entry.key] = exact - base;
    }

    var remainder = total - floorSum;
    if (remainder <= 0) return shares;

    final recipients = winnerPoints.entries
        .where((entry) => entry.value > 0 && receives(entry.key))
        .toList()
      ..sort(
        (a, b) => fractionalParts[b.key]!.compareTo(fractionalParts[a.key]!),
      );

    for (var i = 0; i < recipients.length && remainder > 0; i++) {
      final id = recipients[i].key;
      shares[id] = (shares[id] ?? 0) + 1;
      remainder--;
    }

    return shares;
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
