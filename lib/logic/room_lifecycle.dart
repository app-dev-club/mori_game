import 'bot_logic.dart';
import 'room_authority.dart';
import 'room_config.dart';

/// ルームの自動削除可否（Firebase クリーンアップ用）
class RoomLifecycle {
  static const int maxRoomAgeMs = 24 * 60 * 60 * 1000;

  /// 一定時間更新がなければ放置ルームとみなす（待機ロビー向け）
  static const int inactiveLobbyAgeMs = 15 * 60 * 1000;

  /// シリーズ次戦の自動開始が失敗したときの猶予（ミリ秒）
  static const int seriesContinueGraceMs = 30 * 1000;

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

  static List<String> playerIdsFromData(Map<dynamic, dynamic> data) {
    final players = data['players'] as List?;
    if (players == null) return [];
    return players.map((e) => e.toString()).toList();
  }

  static Set<String> afkPlayerIdsFromData(Map<dynamic, dynamic> data) {
    final afk = data['afkPlayerIds'];
    if (afk is! Map) return {};
    return afk.entries
        .where((e) => e.value == true)
        .map((e) => e.key.toString())
        .toSet();
  }

  /// 接続中かつ離脱扱いでない人間プレイヤーがいるか
  static bool hasPresentHumanPlayers(Map<dynamic, dynamic> data) {
    final presence = data['presence'];
    if (presence is! Map || presence.isEmpty) return false;
    final presentIds = presence.keys.map((e) => e.toString()).toSet();
    final afkIds = afkPlayerIdsFromData(data);
    for (final id in playerIdsFromData(data)) {
      if (BotLogic.isBot(id)) continue;
      if (presentIds.contains(id) && !afkIds.contains(id)) return true;
    }
    return false;
  }

  /// 人間が誰も接続していないが Bot / 離脱代走が必要な対戦中ルーム
  static bool needsBackgroundAutomation(Map<dynamic, dynamic> data) {
    if (needsPostGameSteward(data)) return true;
    if (!isActiveMatch(data)) return false;
    final playerIds = playerIdsFromData(data);
    if (playerIds.isEmpty) return false;

    final presence = data['presence'];
    final presentIds = presence is Map
        ? presence.keys.map((e) => e.toString()).toSet()
        : <String>{};
    final afkIds = afkPlayerIdsFromData(data);
    final authority = RoomAuthority.resolveAuthorityId(
      playerIds: playerIds,
      hostId: data['host']?.toString(),
      presentPlayerIds: presentIds,
      afkPlayerIds: afkIds,
    );
    return RoomAuthority.needsSubstituteRunner(
      gameStarted: true,
      playerIds: playerIds,
      afkPlayerIds: afkIds,
      roomAuthorityId: authority,
      hasAutomatedPlayers:
          playerIds.any((id) => BotLogic.isBot(id) || afkIds.contains(id)),
    );
  }

  /// 試合終了後の精算・ルーム削除をバックグラウンドで行う必要があるか
  static bool needsPostGameSteward(Map<dynamic, dynamic> data) {
    if (data['gameStarted'] != true) return false;
    if (!isMatchEnded(data)) return false;
    if (hasPresentHumanPlayers(data)) return false;
    if (data['seriesRestarting'] == true) return false;
    if (isSeriesContinuationPending(data)) return false;
    return true;
  }

  /// 1戦が終了した（バーストまたはもり決着）
  static bool isMatchEnded(Map<dynamic, dynamic> data) {
    if (data['burstPlayerId'] != null) return true;
    if (data['moriPhase'] == 'finished') return true;
    return false;
  }

  /// シリーズ途中の試合後・次戦待ち・次戦開始処理中か
  static bool isSeriesContinuationPending(Map<dynamic, dynamic> data) {
    if (data['seriesRestarting'] == true) return true;
    if (data['seriesNextMatchAt'] != null) return true;
    if (data['postGameActive'] != true) return false;
    final totalMatches = RoomConfig.resolveMatchCount(data['totalMatches']);
    final completedMatches =
        RoomConfig.resolveNonNegativeInt(data['completedMatches']);
    return totalMatches > 1 && completedMatches < totalMatches;
  }

  /// 対戦がまだ進行中か（代走・Bot 進行の対象）
  static bool isActiveMatch(Map<dynamic, dynamic> data) {
    if (data['gameStarted'] != true) return false;
    if (isSeriesContinuationPending(data)) return true;
    return !isMatchEnded(data);
  }

  /// シリーズ・再戦待ちを含め、ルームを閉じてよい状態か
  static bool isGameFullyConcluded(Map<dynamic, dynamic> data, {required int nowMs}) {
    if (data['gameStarted'] != true) return false;
    if (!isMatchEnded(data)) return false;

    if (data['seriesRestarting'] == true) return false;
    if (data['awaitingGuestStayResponses'] == true) return false;
    if (data['rematchHostRequested'] == true) return false;

    final totalMatches = RoomConfig.resolveMatchCount(data['totalMatches']);
    final completedMatches = RoomConfig.resolveNonNegativeInt(data['completedMatches']);

    if (completedMatches < totalMatches) {
      final seriesNext = data['seriesNextMatchAt'];
      if (seriesNext is num) {
        return nowMs >= seriesNext.round() + seriesContinueGraceMs;
      }
      // 次戦スケジュール前・試合後オーバーレイ中は継続待ち
      return false;
    }

    final postGameEndedAt = data['postGameEndedAt'];
    if (postGameEndedAt is num) {
      return nowMs >= postGameEndedAt.round() + RoomConfig.hostRematchDecisionMs;
    }

    return true;
  }

  /// 公開ルーム一覧に表示するか
  static bool isVisibleInPublicLobby(Map<dynamic, dynamic> data) {
    if (data['isPrivate'] == true) return false;

    final isStarted = data['gameStarted'] == true;
    final players = playerIdsFromData(data);
    if (isStarted && players.isNotEmpty) {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      return !isGameFullyConcluded(data, nowMs: nowMs);
    }

    if (!hasActivePlayers(data)) return false;

    final status = data['roomStatus'] as String? ?? 'open';
    if (isStarted) return true;
    if (!isStarted && status == 'open') return true;
    return false;
  }

  static bool shouldAutoDeleteRoom(Map<dynamic, dynamic> data, {required int nowMs}) {
    final createdAtRaw = data['createdAt'];
    final createdAt = createdAtRaw is num ? createdAtRaw.round() : nowMs;
    if (nowMs - createdAt > maxRoomAgeMs) return true;

    if (isGameFullyConcluded(data, nowMs: nowMs)) return true;

    final spectators = data['spectators'] as Map?;
    final hasSpectators = spectators != null && spectators.isNotEmpty;
    final activePlayers = hasActivePlayers(data);

    // 接続中プレイヤーがいない → 削除（進行中の対戦のみ維持）
    if (!activePlayers && !hasSpectators) {
      if (isActiveMatch(data)) {
        final players = data['players'] as List?;
        if (players != null && players.isNotEmpty) return false;
      }
      return true;
    }

    // プレイヤー不在・観戦のみ → 進行中の対戦・シリーズ継続中は維持
    if (!activePlayers && hasSpectators) {
      if (data['gameStarted'] == true &&
          !isGameFullyConcluded(data, nowMs: nowMs)) {
        return false;
      }
      return data['gameStarted'] != true;
    }

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
