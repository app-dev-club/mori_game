import 'open_skill.dart';

export 'open_skill.dart' show OpenSkill, OpenSkillConstants, OpenSkillRating;

/// OpenSkill ベースのレーティング計算
class RatingLogic {
  static const int defaultRating = OpenSkillConstants.displayRatingOffset;

  static OpenSkillRating defaultSkillRating() => OpenSkillConstants.defaultRating();

  static int displayRating(OpenSkillRating rating) => OpenSkill.displayRating(rating);

  static String formatSignedDelta(int delta) =>
      delta >= 0 ? '+$delta' : '$delta';

  static String formatSigma(double sigma) => sigma.toStringAsFixed(2);

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

  /// OpenSkill で μ・σ を更新し、表示レートの増減も返す
  static Map<String, ({OpenSkillRating oldRating, OpenSkillRating newRating, int ratingDelta})>
      computeSkillUpdates({
    required Map<String, OpenSkillRating> oldRatings,
    required List<String> playerIds,
    required Map<String, int> finalPoints,
  }) {
    if (playerIds.length < 2) return {};

    final ranked = rankByPoints(playerIds, finalPoints);
    final rankById = {for (final entry in ranked) entry.id: entry.rank.toDouble()};

    final teams = playerIds
        .map((id) => [oldRatings[id] ?? defaultSkillRating()])
        .toList();
    final ranks = playerIds.map((id) => rankById[id]!).toList();

    final updatedTeams = OpenSkill.rate(teams, ranks);
    final updates = <String, ({OpenSkillRating oldRating, OpenSkillRating newRating, int ratingDelta})>{};

    for (var i = 0; i < playerIds.length; i++) {
      final id = playerIds[i];
      final oldRating = oldRatings[id] ?? defaultSkillRating();
      final newRating = updatedTeams[i].first;
      final delta = displayRating(newRating) - displayRating(oldRating);
      updates[id] = (oldRating: oldRating, newRating: newRating, ratingDelta: delta);
    }
    return updates;
  }

  static String buildSeriesSummary({
    required List<({String id, int points, int rank})> ranked,
    required Map<String, OpenSkillRating> oldRatings,
    required Map<String, ({OpenSkillRating oldRating, OpenSkillRating newRating, int ratingDelta})> updates,
    required Map<String, String> displayNames,
  }) {
    final buffer = StringBuffer('【最終順位・レート】\n');
    for (final entry in ranked) {
      final name = displayNames[entry.id] ?? entry.id;
      final old = oldRatings[entry.id] ?? defaultSkillRating();
      final update = updates[entry.id];
      final neu = update?.newRating ?? old;
      final delta = update?.ratingDelta ?? 0;
      final newDisplay = displayRating(neu);
      buffer.writeln(
        '${entry.rank}位 $name ${entry.points}点 → レート $newDisplay (${formatSignedDelta(delta)}) · σ ${formatSigma(neu.sigma)}',
      );
    }
    return buffer.toString().trimRight();
  }
}
