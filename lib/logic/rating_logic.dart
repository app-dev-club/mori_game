import 'dart:math';

/// レーティング計算（ELO系・複数人対戦）
class RatingLogic {
  static const int defaultRating = 1500;
  static const int kFactor = 32;

  static String formatSignedDelta(int delta) =>
      delta >= 0 ? '+$delta' : '$delta';

  /// ポイント降順の順位（同点は同順位）
  static List<({String id, int points, int rank})> rankByPoints(
    List<String> playerIds,
    Map<String, int> finalPoints,
  ) {
    final entries = playerIds
        .map((id) => (id: id, points: finalPoints[id] ?? 0))
        .toList()
      ..sort((a, b) => b.points.compareTo(a.points));

    final ranked = <({String id, int points, int rank})>[];
    for (var i = 0; i < entries.length; i++) {
      var rank = i + 1;
      if (i > 0 && entries[i].points == entries[i - 1].points) {
        rank = ranked[i - 1].rank;
      }
      ranked.add((id: entries[i].id, points: entries[i].points, rank: rank));
    }
    return ranked;
  }

  /// 同室プレイヤーのレートと順位（ポイント）から増減を算出
  static Map<String, int> computeDeltas(
    Map<String, int> ratings,
    List<String> playerIds,
    Map<String, int> finalPoints,
  ) {
    final n = playerIds.length;
    if (n < 2) return {};

    final deltas = <String, int>{};
    for (final id in playerIds) {
      final myRating = ratings[id] ?? defaultRating;
      final myPoints = finalPoints[id] ?? 0;
      var actualScore = 0.0;
      var expectedScore = 0.0;

      for (final oppId in playerIds) {
        if (oppId == id) continue;
        final oppPoints = finalPoints[oppId] ?? 0;
        if (myPoints > oppPoints) {
          actualScore += 1;
        } else if (myPoints == oppPoints) {
          actualScore += 0.5;
        }

        final oppRating = ratings[oppId] ?? defaultRating;
        expectedScore += 1 / (1 + pow(10, (oppRating - myRating) / 400));
      }

      final divisor = n - 1;
      deltas[id] = (kFactor * (actualScore / divisor - expectedScore / divisor)).round();
    }
    return deltas;
  }

  static String buildSeriesSummary({
    required List<({String id, int points, int rank})> ranked,
    required Map<String, int> oldRatings,
    required Map<String, int> deltas,
    required Map<String, String> displayNames,
  }) {
    final buffer = StringBuffer('【最終順位・レート】\n');
    for (final entry in ranked) {
      final name = displayNames[entry.id] ?? entry.id;
      final old = oldRatings[entry.id] ?? defaultRating;
      final delta = deltas[entry.id] ?? 0;
      final neu = old + delta;
      buffer.writeln(
        '${entry.rank}位 $name ${entry.points}点 → レート $neu (${formatSignedDelta(delta)})',
      );
    }
    return buffer.toString().trimRight();
  }
}
