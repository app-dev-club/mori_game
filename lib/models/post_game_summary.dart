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

  const PostGamePlayerRow({
    required this.name,
    this.matchDelta,
    required this.totalPoints,
    required this.rank,
    this.rating,
    this.ratingDelta,
    this.morrieDelta,
    this.morrieBalance,
  });
}

/// 試合終了オーバーレイの表示データ
class PostGameSummary {
  final String title;
  final List<PostGamePlayerRow> players;
  final bool showRating;
  final bool showMorrie;
  final String? resultMessage;

  const PostGameSummary({
    required this.title,
    required this.players,
    this.showRating = false,
    this.showMorrie = false,
    this.resultMessage,
  });
}
