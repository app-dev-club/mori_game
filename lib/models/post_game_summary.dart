/// 試合終了オーバーレイ用の1プレイヤー分の結果
class PostGamePlayerRow {
  final String name;
  final int? matchDelta;
  final int totalPoints;
  final int rank;
  final int? rating;
  final int? ratingDelta;
  final int? morrieDelta;
  final int? morrieBalance;
  /// Bot 飛び後のモリー回復が反映済みの残高か
  final bool morrieBalanceIsRecovered;

  const PostGamePlayerRow({
    required this.name,
    this.matchDelta,
    required this.totalPoints,
    required this.rank,
    this.rating,
    this.ratingDelta,
    this.morrieDelta,
    this.morrieBalance,
    this.morrieBalanceIsRecovered = false,
  });
}

/// 試合終了オーバーレイの表示データ
class PostGameSummary {
  final String title;
  final List<PostGamePlayerRow> players;
  final bool showRating;
  final bool showMorrie;
  /// 7枚バースト（得点 -2）のメッセージ
  final String? cardBurstMessage;
  /// モリー飛びのメッセージ
  final String? morrieBurstMessage;
  /// モリー移動・減算のサマリー（飛び文言を除く）
  final String? morrieResultMessage;

  /// Bot 飛び後の回復モリーが残高に含まれる行があるか
  bool get showsRecoveredMorrieBalance =>
      players.any((row) => row.morrieBalanceIsRecovered);

  const PostGameSummary({
    required this.title,
    required this.players,
    this.showRating = false,
    this.showMorrie = false,
    this.cardBurstMessage,
    this.morrieBurstMessage,
    this.morrieResultMessage,
  });
}
