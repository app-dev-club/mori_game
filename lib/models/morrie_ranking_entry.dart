/// モリーランキングの1行分
class MorrieRankingEntry {
  final String id;
  final String playerName;
  final int morrieBalance;
  final int rank;
  final bool isBot;

  const MorrieRankingEntry({
    required this.id,
    required this.playerName,
    required this.morrieBalance,
    required this.rank,
    this.isBot = false,
  });
}
