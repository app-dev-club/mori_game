/// ルームの自動削除可否（Firebase クリーンアップ用）
class RoomLifecycle {
  static const int maxRoomAgeMs = 24 * 60 * 60 * 1000;

  /// 一定時間更新がなければ放置ルームとみなす（待機ロビー向け）
  static const int inactiveLobbyAgeMs = 15 * 60 * 1000;

  /// 接続中のプレイヤーがいるか（presence のみを信頼する）
  static bool hasActivePlayers(Map<dynamic, dynamic> data) {
    if (!data.containsKey('presence')) {
      // presence 未導入の古いルーム: players は切断後も残るため接続中とはみなさない
      return false;
    }
    final presence = data['presence'];
    if (presence is! Map || presence.isEmpty) return false;
    return true;
  }

  static bool shouldAutoDeleteRoom(Map<dynamic, dynamic> data, {required int nowMs}) {
    final createdAtRaw = data['createdAt'];
    final createdAt = createdAtRaw is num ? createdAtRaw.round() : nowMs;
    if (nowMs - createdAt > maxRoomAgeMs) return true;

    final spectators = data['spectators'] as Map?;
    final hasSpectators = spectators != null && spectators.isNotEmpty;
    final activePlayers = hasActivePlayers(data);

    // 接続中プレイヤーがいない → 削除（対戦中の放棄ルームも含む）
    if (!activePlayers && !hasSpectators) return true;

    // プレイヤー不在・観戦のみ → 削除
    if (!activePlayers && hasSpectators) return true;

    // 待機ロビーで長時間更新なし → 削除（stale な presence / players を含む）
    if (data['gameStarted'] != true &&
        !_isProtectedRoomState(data) &&
        _isInactiveRoom(data, nowMs: nowMs)) {
      return true;
    }

    // 接続中プレイヤーがいる場合のみ以下で維持判断
    if (data['gameStarted'] == true) return false;
    if (_isProtectedRoomState(data)) return false;

    return false;
  }

  static bool _isProtectedRoomState(Map<dynamic, dynamic> data) {
    if (data['postGameActive'] == true) return true;
    if (data['awaitingGuestStayResponses'] == true) return true;
    if (data['seriesRestarting'] == true) return true;
    if (data['seriesNextMatchAt'] != null) return true;
    return false;
  }

  static bool _isInactiveRoom(Map<dynamic, dynamic> data, {required int nowMs}) {
    final lastActivity = _lastActivityMs(data);
    if (lastActivity == null) return false;
    return nowMs - lastActivity >= inactiveLobbyAgeMs;
  }

  static int? _lastActivityMs(Map<dynamic, dynamic> data) {
    int? latest;

    void consider(dynamic value) {
      if (value is num) {
        final ms = value.round();
        if (latest == null || ms > latest!) latest = ms;
      }
    }

    consider(data['createdAt']);
    consider(data['deckResetAt']);
    consider(data['moriDeclaredAt']);
    consider(data['postGameEndedAt']);
    consider(data['rematchStartedAt']);
    consider(data['seriesNextMatchAt']);

    final presence = data['presence'];
    if (presence is Map) {
      for (final value in presence.values) {
        consider(value);
      }
    }

    return latest;
  }
}
