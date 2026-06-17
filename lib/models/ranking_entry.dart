/// レートランキングの1行分
class RankingEntry {
  final String id;
  final String playerName;
  final int rating;
  final int gamesPlayed;
  final bool isBot;
  final int rank;

  const RankingEntry({
    required this.id,
    required this.playerName,
    required this.rating,
    required this.gamesPlayed,
    required this.isBot,
    required this.rank,
  });
}
