import '../models/post_game_summary.dart';
import 'bot_logic.dart';

class PostGameSummaryBuilder {
  static PostGameSummary build({
    required List<String> roster,
    required Map<String, String> names,
    required Map<String, int> playerPoints,
    required Map<String, int> lastMatchPointDeltas,
    required Map<String, Map<String, dynamic>> seriesRatingDetails,
    required Map<String, Map<String, dynamic>> seriesMorrieDetails,
    required Map<String, int> lastMatchMorrieDeltas,
    required Map<String, int> lastMatchMorrieBalances,
    Map<String, int> currentMorrieBalances = const {},
    String? morrieBurstPlayerId,
    bool morrieBurstRecoveryApplied = false,
    required int morrieRate,
    required int totalMatches,
    required int completedMatches,
    required bool seriesComplete,
    String? cardBurstMessage,
    String? morrieBurstMessage,
    String? morrieResultMessage,
  }) {
    if (roster.isEmpty) {
      return const PostGameSummary(title: '試合結果', players: []);
    }

    final showRating = seriesComplete && seriesRatingDetails.isNotEmpty;
    final showMorrie = morrieRate > 0;
    final rows = <PostGamePlayerRow>[];

    for (final id in roster) {
      final detail = seriesRatingDetails[id];
      final morrieDetail = seriesMorrieDetails[id];
      final ratingValue = detail?['rating'];
      final deltaValue = detail?['ratingDelta'];
      final rankValue = detail?['rank'] ?? morrieDetail?['rank'];
      final pointsValue = detail?['points'] ?? morrieDetail?['points'];
      final morrieBalanceDetail = morrieDetail?['morrieBalance'];
      final morrieDeltaValue =
          morrieRate > 0 ? lastMatchMorrieDeltas[id] ?? 0 : null;
      final morrieBalanceValue = currentMorrieBalances[id] ??
          (seriesComplete
              ? (morrieBalanceDetail is num
                  ? morrieBalanceDetail.round()
                  : lastMatchMorrieBalances[id])
              : lastMatchMorrieBalances[id]);
      final morrieBalanceIsRecovered = morrieBurstRecoveryApplied &&
          morrieBurstPlayerId == id &&
          BotLogic.isBot(id);

      rows.add(
        PostGamePlayerRow(
          name: names[id] ?? 'プレイヤー',
          matchDelta: lastMatchPointDeltas[id],
          totalPoints: pointsValue is num
              ? pointsValue.round()
              : (playerPoints[id] ?? 0),
          rank: rankValue is num ? rankValue.round() : 0,
          rating: ratingValue is num ? ratingValue.round() : null,
          ratingDelta: deltaValue is num ? deltaValue.round() : null,
          morrieDelta: morrieDeltaValue,
          morrieBalance: morrieBalanceValue,
          morrieBalanceIsRecovered: morrieBalanceIsRecovered,
        ),
      );
    }

    if (showRating || showMorrie) {
      rows.sort((a, b) {
        final byRank = a.rank.compareTo(b.rank);
        if (byRank != 0) return byRank;
        return b.totalPoints.compareTo(a.totalPoints);
      });
    } else {
      rows.sort((a, b) => b.totalPoints.compareTo(a.totalPoints));
      for (var i = 0; i < rows.length; i++) {
        final row = rows[i];
        rows[i] = PostGamePlayerRow(
          name: row.name,
          matchDelta: row.matchDelta,
          totalPoints: row.totalPoints,
          rank: i + 1,
          rating: row.rating,
          ratingDelta: row.ratingDelta,
          morrieDelta: row.morrieDelta,
          morrieBalance: row.morrieBalance,
          morrieBalanceIsRecovered: row.morrieBalanceIsRecovered,
        );
      }
    }

    final title = seriesComplete
        ? '全$totalMatches戦 結果'
        : (totalMatches > 1 ? '第$completedMatches戦終了' : '試合結果');

    return PostGameSummary(
      title: title,
      players: rows,
      showRating: showRating,
      showMorrie: showMorrie,
      cardBurstMessage: cardBurstMessage,
      morrieBurstMessage: morrieBurstMessage,
      morrieResultMessage: morrieResultMessage,
    );
  }
}
