/// ルームの自動削除可否（Firebase クリーンアップ用）
class RoomLifecycle {
  static const int maxRoomAgeMs = 24 * 60 * 60 * 1000;

  static bool shouldAutoDeleteRoom(Map<dynamic, dynamic> data, {required int nowMs}) {
    final players = data['players'] as List?;
    final hasPlayers = players != null && players.isNotEmpty;
    final spectators = data['spectators'] as Map?;
    final hasSpectators = spectators != null && spectators.isNotEmpty;

    final createdAtRaw = data['createdAt'];
    final createdAt = createdAtRaw is num ? createdAtRaw.round() : nowMs;
    if (nowMs - createdAt > maxRoomAgeMs) return true;

    if (!hasPlayers && !hasSpectators) return true;

    // 対戦中・試合後・シリーズ継続中は削除しない
    if (data['gameStarted'] == true) return false;
    if (data['postGameActive'] == true) return false;
    if (data['seriesRestarting'] == true) return false;
    if (data['seriesNextMatchAt'] != null) return false;
    if (data['awaitingGuestStayResponses'] == true) return false;

    // プレイヤーが残っているロビーは維持（ホスト切断で closed になっても即削除しない）
    if (hasPlayers) return false;

    // 観戦のみの異常状態
    return !hasSpectators;
  }
}
