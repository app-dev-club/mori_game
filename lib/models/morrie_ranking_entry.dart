/// モリーランキングの1行分
class MorrieRankingEntry {
  final String id;
  final String playerName;
  final int morrieBalance;
  final int rank;

  const MorrieRankingEntry({
    required this.id,
    required this.playerName,
    required this.morrieBalance,
    required this.rank,
  });
}
