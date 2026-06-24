import 'bot_logic.dart';

/// ホスト離脱時などに Bot / 代走ロジックを実行するクライアントを決める
class RoomAuthority {
  static Set<String> parsePresentPlayerIds(dynamic presence) {
    if (presence is! Map) return {};
    return presence.keys.map((e) => e.toString()).toSet();
  }

  static Set<String> parseAfkPlayerIds(dynamic afk) {
    if (afk is! Map) return {};
    return afk.entries
        .where((e) => e.value == true)
        .map((e) => e.key.toString())
        .toSet();
  }

  /// 接続中かつ離脱扱いでないプレイヤーのうち、ホストを優先して権限者を返す
  static String? resolveAuthorityId({
    required List<String> playerIds,
    required String? hostId,
    required Set<String> presentPlayerIds,
    required Set<String> afkPlayerIds,
  }) {
    bool isEligible(String id) =>
        playerIds.contains(id) &&
        presentPlayerIds.contains(id) &&
        !afkPlayerIds.contains(id);

    if (hostId != null && isEligible(hostId)) {
      return hostId;
    }
    for (final id in playerIds) {
      if (isEligible(id)) return id;
    }
    return null;
  }

  /// 接続中のプレイヤーがルームを進行できないとき true
  static bool needsSubstituteRunner({
    required bool gameStarted,
    required List<String> playerIds,
    required Set<String> afkPlayerIds,
    required String? roomAuthorityId,
    bool hasAutomatedPlayers = true,
  }) {
    if (!gameStarted || playerIds.isEmpty) return false;
    final hasConnectedAuthority = roomAuthorityId != null &&
        !afkPlayerIds.contains(roomAuthorityId);
    if (hasConnectedAuthority) return false;
    return hasAutomatedPlayers || playerIds.any((id) => !BotLogic.isBot(id));
  }
}
