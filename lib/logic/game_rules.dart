import 'dart:math';

import '../features/game/game_board_view.dart';

class GameRules {
  static const int maxHandSize = 7;

  /// バースト判定
  static bool isBurst(int handCount, bool canPlayDrawnCard) {
    return handCount >= maxHandSize && !canPlayDrawnCard;
  }

  /// ターン中にドロー可能か（1ターン1回・手札上限7枚）
  static bool canDraw(int handCount, String? lastDrawerId, String myId) {
    return handCount < maxHandSize && lastDrawerId != myId;
  }

  /// ドロー競合フェーズ（手札6枚以下でドロー後）が有効か
  static bool isDrawCompetitivePhase(
    bool isDrawCompetitive,
    String? lastDrawerId,
  ) {
    return isDrawCompetitive && lastDrawerId != null;
  }

  /// ドローした直後の「次のプレイヤー」か
  static bool isPlayerAfterDrawer(
    String? lastDrawerId,
    List<String> players,
    String myId,
  ) {
    if (lastDrawerId == null || players.isEmpty) return false;
    final drawerIdx = players.indexOf(lastDrawerId);
    if (drawerIdx < 0) return false;
    return players[(drawerIdx + 1) % players.length] == myId;
  }

  /// 盤面表示用: 自分の次の手番から時計回りに並べた相手（playerIds の index 付き）
  static List<MapEntry<int, String>> opponentEntriesClockwiseFrom(
    String myId,
    List<String> playerIds,
  ) {
    final myIdx = playerIds.indexOf(myId);
    if (myIdx < 0 || playerIds.length <= 1) return const [];
    return List.generate(playerIds.length - 1, (i) {
      final idx = (myIdx + i + 1) % playerIds.length;
      return MapEntry(idx, playerIds[idx]);
    });
  }

  /// 盤面表示用: 自分の次の手番から時計回りに並べた相手 ID 一覧
  static List<String> opponentsClockwiseFrom(
    String myId,
    List<String> playerIds,
  ) => opponentEntriesClockwiseFrom(
    myId,
    playerIds,
  ).map((e) => e.value).toList();

  /// 新しい1戦の手番順（players 配列の並び）をランダムに決める
  static List<String> shuffledPlayerOrder(
    List<String> playerIds, [
    Random? random,
  ]) {
    final ordered = List<String>.from(playerIds);
    ordered.shuffle(random ?? Random());
    return ordered;
  }

  /// ドロー競合中にカードを出せるか（ドローした人 or 次のプレイヤー）
  static bool canPlayInDrawCompetition({
    required bool isDrawCompetitive,
    required String? lastDrawerId,
    required List<String> players,
    required String myId,
  }) {
    if (!isDrawCompetitivePhase(isDrawCompetitive, lastDrawerId)) return false;
    return lastDrawerId == myId ||
        isPlayerAfterDrawer(lastDrawerId, players, myId);
  }

  /// ドロー競合中に山札から引けるか
  static bool canDrawInCompetition({
    required bool isDrawCompetitive,
    required String? lastDrawerId,
    required List<String> players,
    required String myId,
    required int handCount,
  }) {
    if (!isDrawCompetitivePhase(isDrawCompetitive, lastDrawerId)) return false;
    if (!isPlayerAfterDrawer(lastDrawerId, players, myId)) return false;
    return canDraw(handCount, lastDrawerId, myId);
  }

  /// もり判定ロジック（手札全体で計算、JQK対応、ジョーカー除外）
  static bool isValidMori(int fieldNumber, List<CardWidget> hand) {
    if (fieldNumber == -1 || hand.isEmpty) return false;

    // ジョーカーを除外したリストを作成（枚数カウント除外ルール）
    final numbers = hand
        .where((c) => c.suit != Suit.joker)
        .map((c) => c.number)
        .toList();

    int effectiveCount = numbers.length;

    // 手札が1枚の場合
    if (effectiveCount == 1) {
      return numbers[0] == fieldNumber;
    }

    // 手札が2枚の場合（四則演算）
    if (effectiveCount == 2) {
      int a = numbers[0];
      int b = numbers[1];
      return (a + b == fieldNumber) ||
          (a - b == fieldNumber) ||
          (b - a == fieldNumber) ||
          (a * b == fieldNumber) ||
          (b != 0 && a % b == 0 && a ~/ b == fieldNumber) ||
          (a != 0 && b % a == 0 && b ~/ a == fieldNumber);
    }

    // 手札が3枚以上の場合（すべての和）
    if (effectiveCount >= 3) {
      int sum = numbers.fold(0, (prev, n) => prev + n);
      return sum == fieldNumber;
    }

    return false;
  }

  /// もり宣言可否（相手が出したカードに対してのみ。山札めくり `system` には不可）
  static bool canDeclareMori({
    required int fieldNumber,
    required List<CardWidget> hand,
    required String moriPhase,
    required String? lastPlayerId,
    required String playerId,
    required List<String> moriDeclaredPlayerIds,
  }) {
    if (moriPhase != 'none' || fieldNumber == -1) return false;
    if (moriDeclaredPlayerIds.contains(playerId)) return false;
    if (lastPlayerId == null ||
        lastPlayerId == playerId ||
        lastPlayerId == 'system') {
      return false;
    }
    return isValidMori(fieldNumber, hand);
  }

  /// もり返し宣言可否
  static bool canDeclareMoriGaeshi({
    required int fieldNumber,
    required List<CardWidget> hand,
    required String moriPhase,
    required String? lastMoriPlayerId,
    required String playerId,
    required List<String> moriDeclaredPlayerIds,
  }) {
    if (moriPhase != 'mori_declared' || fieldNumber == -1) return false;
    if (moriDeclaredPlayerIds.contains(playerId)) return false;
    if (lastMoriPlayerId == null || lastMoriPlayerId == playerId) return false;
    return isValidMori(fieldNumber, hand);
  }

  static bool hasJoker(List<CardWidget> hand) =>
      hand.any((c) => c.suit == Suit.joker);

  /// Bot 等が「相手の手札枚数」を見るとき、オープンジョーカー済みはジョーカー以外で数える
  static int decisionHandCount({
    required String playerId,
    required Map<String, int> handCounts,
    required Set<String> openJokerPlayerIds,
    Map<String, List<CardWidget>>? playerHands,
  }) {
    final raw = handCounts[playerId] ?? 0;
    if (!openJokerPlayerIds.contains(playerId)) return raw;

    final hand = playerHands?[playerId];
    if (hand != null) {
      return hand.where((c) => c.suit != Suit.joker).length;
    }
    // オープンジョーカーは手札にジョーカー1枚を含む
    return (raw - 1).clamp(0, raw);
  }

  static bool isJokerPlusOneHand(List<CardWidget> hand) {
    if (!hasJoker(hand)) return false;
    return hand.where((c) => c.suit != Suit.joker).length == 1;
  }

  /// オープンジョーカー宣言可否
  static bool canOpenJoker({
    required List<CardWidget> hand,
    required String playerId,
    required Set<String> openJokerPlayerIds,
    required bool gameStarted,
    required String moriPhase,
  }) {
    if (!gameStarted || moriPhase != 'none') return false;
    if (openJokerPlayerIds.contains(playerId)) return false;
    return hasJoker(hand);
  }

  /// 場に実際のジョーカーが出ているか（未めくりのプレースホルダー `-1/joker` は除く）
  static bool isJokerOnField(int fieldNumber, Suit fieldSuit) {
    return fieldSuit == Suit.joker && fieldNumber != -1;
  }

  /// 通常プレイ判定
  /// [isInitialPhase] が true のときは同じ数字のみ（ジョーカー場は例外で任意のカード可）
  static bool canPlayNormal(
    int fieldNumber,
    Suit fieldSuit,
    CardWidget card, {
    bool isInitialPhase = false,
  }) {
    if (fieldNumber == -1) return false;
    if (card.suit == Suit.joker) return false;
    if (isJokerOnField(fieldNumber, fieldSuit)) return true;
    if (isInitialPhase) return card.number == fieldNumber;
    return card.number == fieldNumber || card.suit == fieldSuit;
  }

  /// 山札から引ける権利があるか（観戦・リプレイのパネル強調用）
  static bool hasDrawPrivilege({
    required String playerId,
    required List<String> playerIds,
    required int? turnIndex,
    required bool isDrawCompetitive,
    required String? lastDrawerId,
    required String? lastPlayerId,
    required bool isInitialPhase,
    required int fieldNumber,
    required int handCount,
  }) {
    if (playerIds.isEmpty || handCount >= maxHandSize) return false;
    if (fieldNumber < 0) return false;

    // 山札めくり直後（まだ誰も手札から出していない）
    if (isInitialPhase && (lastPlayerId == 'system' || lastPlayerId == null)) {
      return false;
    }

    if (isDrawCompetitivePhase(isDrawCompetitive, lastDrawerId)) {
      return canDrawInCompetition(
        isDrawCompetitive: isDrawCompetitive,
        lastDrawerId: lastDrawerId,
        players: playerIds,
        myId: playerId,
        handCount: handCount,
      );
    }

    final holderId = drawPrivilegeHolderId(
      playerIds: playerIds,
      turnIndex: turnIndex,
      lastPlayerId: lastPlayerId,
    );
    if (holderId == null) return false;
    return holderId == playerId && canDraw(handCount, lastDrawerId, playerId);
  }

  /// 通常時に山札から引けるプレイヤー（場に出した人の次）
  static String? drawPrivilegeHolderId({
    required List<String> playerIds,
    required int? turnIndex,
    required String? lastPlayerId,
  }) {
    if (playerIds.isEmpty) return null;

    if (lastPlayerId != null &&
        lastPlayerId != 'system' &&
        playerIds.contains(lastPlayerId)) {
      final idx = playerIds.indexOf(lastPlayerId);
      return playerIds[(idx + 1) % playerIds.length];
    }

    if (turnIndex != null) {
      return playerIds[turnIndex % playerIds.length];
    }
    return null;
  }

  /// 7枚目を引いた直後、出すカードを選ぶ必要があるか
  static bool mustPlayAfterSeventhDraw({
    required int handCount,
    required String? lastDrawerId,
    required String myId,
    required int currentTurnIndex,
    required List<String> players,
  }) {
    final myIdx = players.indexOf(myId);
    if (myIdx < 0) return false;
    final isMyTurn =
        players.isNotEmpty && (currentTurnIndex % players.length == myIdx);
    return isMyTurn && handCount >= maxHandSize && lastDrawerId == myId;
  }

  /// 自動プレイタイマーを開始すべきか（ドロー可能なターン、または7枚目引き後）
  static bool shouldAutoPlayOnTimeout({
    required bool gameStarted,
    required bool isInitialPhase,
    required int fieldNumber,
    required String moriPhase,
    required int currentTurnIndex,
    required List<String> players,
    required String myId,
    required int handCount,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
  }) {
    if (!gameStarted ||
        isInitialPhase ||
        fieldNumber == -1 ||
        moriPhase != 'none') {
      return false;
    }
    final myIdx = players.indexOf(myId);
    if (myIdx < 0) return false;
    final isMyTurn =
        players.isNotEmpty && (currentTurnIndex % players.length == myIdx);
    final canDrawInCompetition = GameRules.canDrawInCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: players,
      myId: myId,
      handCount: handCount,
    );
    final canDrawNow =
        (isMyTurn || canDrawInCompetition) &&
        canDraw(handCount, lastDrawerId, myId);
    final mustPlaySeventh = mustPlayAfterSeventhDraw(
      handCount: handCount,
      lastDrawerId: lastDrawerId,
      myId: myId,
      currentTurnIndex: currentTurnIndex,
      players: players,
    );
    return canDrawNow || mustPlaySeventh;
  }

  /// 自動で出せる合法手の手札インデックス（無ければ null）
  static int? findPlayableCardIndex({
    required int fieldNumber,
    required Suit fieldSuit,
    required List<CardWidget> hand,
    required bool isInitialPhase,
    required int currentTurnIndex,
    required List<String> players,
    required String myId,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
  }) {
    if (fieldNumber == -1 || hand.isEmpty) return null;

    final myIdx = players.indexOf(myId);
    if (myIdx < 0) return null;

    final isJokerField = isJokerOnField(fieldNumber, fieldSuit);

    if (isInitialPhase) {
      for (var i = 0; i < hand.length; i++) {
        if (canPlayNormal(
          fieldNumber,
          fieldSuit,
          hand[i],
          isInitialPhase: true,
        )) {
          return i;
        }
      }
      return null;
    }

    final isServerTurn = currentTurnIndex % players.length == myIdx;
    final isLastDrawer = lastDrawerId == myId;
    final isCompetitiveParticipant = canPlayInDrawCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: players,
      myId: myId,
    );

    for (var i = 0; i < hand.length; i++) {
      final card = hand[i];
      final isInterrupt = card.suit != Suit.joker && card.number == fieldNumber;
      final usesTurnPlayLimit =
          isServerTurn || isLastDrawer || isCompetitiveParticipant;

      if (usesTurnPlayLimit &&
          hasPlayedThisTurn &&
          !isInterrupt &&
          !isJokerField) {
        continue;
      }

      if (isServerTurn ||
          isLastDrawer ||
          isCompetitiveParticipant ||
          isInterrupt ||
          isJokerField) {
        if (canPlayNormal(fieldNumber, fieldSuit, card) || isInterrupt) {
          return i;
        }
      }
    }
    return null;
  }

  /// 初期フェーズで場にカードがあり、自動めくりタイマーを開始すべきか
  static bool shouldStartInitialPhaseAutoFlip({
    required bool isInitialPhase,
    required int fieldNumber,
    required String moriPhase,
    required bool gameStarted,
  }) {
    return isInitialPhase &&
        fieldNumber != -1 &&
        moriPhase == 'none' &&
        gameStarted;
  }
}
