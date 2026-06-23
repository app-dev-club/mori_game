import 'dart:math';

import '../features/game/game_board_view.dart';
import 'game_rules.dart';

enum BotActionType { none, mori, play, draw, burst }

class BotDecision {
  final BotActionType type;
  final int? cardIndex;

  const BotDecision._(this.type, [this.cardIndex]);

  const BotDecision.none() : this._(BotActionType.none);
  const BotDecision.mori() : this._(BotActionType.mori);
  const BotDecision.play(int index) : this._(BotActionType.play, index);
  const BotDecision.draw() : this._(BotActionType.draw);
  const BotDecision.burst() : this._(BotActionType.burst);
}

/// Botプレイヤーの識別と行動決定
class BotLogic {
  static const String idPrefix = 'bot_';

  /// 8人対戦のため、Bot は最大7体（bot_1 … bot_7）まで
  static const int maxBotSlot = 7;

  static bool isBot(String playerId) => playerId.startsWith(idPrefix);

  static bool isRetiredBotId(String playerId) {
    final slot = slotFromBotId(playerId);
    return slot != null && slot > maxBotSlot;
  }

  static bool isAssignableBotSlot(int slot) => slot >= 1 && slot <= maxBotSlot;

  static bool hasAvailableBotSlot(Iterable<String> playerIds) =>
      tryNextBotId(playerIds) != null;

  static String botIdForSlot(int slot) => '$idPrefix$slot';

  static int? slotFromBotId(String playerId) {
    if (!isBot(playerId)) return null;
    return int.tryParse(playerId.substring(idPrefix.length));
  }

  static String botDisplayName(String botId) {
    final slot = slotFromBotId(botId);
    return slot != null ? 'Bot $slot' : 'Bot';
  }

  /// 未使用の bot_N ID を返す（bot_1 … bot_7）。空きがなければ null
  static String? tryNextBotId(Iterable<String> playerIds) {
    final usedSlots = playerIds
        .where(isBot)
        .map(slotFromBotId)
        .whereType<int>()
        .toSet();
    for (var slot = 1; slot <= maxBotSlot; slot++) {
      if (!usedSlots.contains(slot)) return botIdForSlot(slot);
    }
    return null;
  }

  static String nextBotName(Iterable<String> playerIds) {
    final botId = tryNextBotId(playerIds);
    return botId != null ? botDisplayName(botId) : 'Bot';
  }

  static bool canDeclareMori({
    required int fieldNumber,
    required List<CardWidget> hand,
    required String moriPhase,
    required String? lastPlayerId,
    required String playerId,
    required List<String> moriDeclaredPlayerIds,
  }) =>
      GameRules.canDeclareMori(
        fieldNumber: fieldNumber,
        hand: hand,
        moriPhase: moriPhase,
        lastPlayerId: lastPlayerId,
        playerId: playerId,
        moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      );

  static bool canDeclareMoriGaeshi({
    required int fieldNumber,
    required List<CardWidget> hand,
    required String moriPhase,
    required String? lastMoriPlayerId,
    required String playerId,
    required List<String> moriDeclaredPlayerIds,
  }) =>
      GameRules.canDeclareMoriGaeshi(
        fieldNumber: fieldNumber,
        hand: hand,
        moriPhase: moriPhase,
        lastMoriPlayerId: lastMoriPlayerId,
        playerId: playerId,
        moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      );

  /// 持ち時間内でランダムな操作遅延（ミリ秒）を返す
  static int randomActionDelayMs({
    required int maxMs,
    int minMs = 400,
    Random? random,
  }) {
    final rng = random ?? Random();
    final cappedMax = maxMs < minMs ? minMs : maxMs;
    if (cappedMax <= minMs) return minMs;
    return minMs + rng.nextInt(cappedMax - minMs + 1);
  }

  static bool shouldBotAct({
    required bool gameStarted,
    required bool isInitialPhase,
    required int fieldNumber,
    required String moriPhase,
    required int currentTurnIndex,
    required List<String> players,
    required String botId,
    required List<CardWidget> hand,
    required Map<String, int> handCounts,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
    required Suit fieldSuit,
    required String? lastPlayerId,
    required String? lastMoriPlayerId,
    required List<String> moriDeclaredPlayerIds,
  }) {
    if (!gameStarted || fieldNumber == -1) return false;
    if (moriPhase == 'finished') return false;
    if (moriPhase == 'mori_declared') {
      return canDeclareMoriGaeshi(
        fieldNumber: fieldNumber,
        hand: hand,
        moriPhase: moriPhase,
        lastMoriPlayerId: lastMoriPlayerId,
        playerId: botId,
        moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      );
    }
    return decideAction(
      gameStarted: gameStarted,
      isInitialPhase: isInitialPhase,
      fieldNumber: fieldNumber,
      fieldSuit: fieldSuit,
      moriPhase: moriPhase,
      currentTurnIndex: currentTurnIndex,
      players: players,
      botId: botId,
      hand: hand,
      handCounts: handCounts,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      hasPlayedThisTurn: hasPlayedThisTurn,
      lastPlayerId: lastPlayerId,
      moriDeclaredPlayerIds: moriDeclaredPlayerIds,
    ).type != BotActionType.none;
  }

  /// 他プレイヤーに手札2枚の人がいるか
  static bool anotherPlayerHasTwoCards({
    required String botId,
    required List<String> players,
    required Map<String, int> handCounts,
  }) {
    for (final playerId in players) {
      if (playerId == botId) continue;
      if ((handCounts[playerId] ?? 0) == 2) return true;
    }
    return false;
  }

  /// 手札2枚・3枚・6枚以上のときは、相手が2枚でもカードを出す
  static bool shouldPlayDespiteTwoCardOpponent(int botHandLength) =>
      botHandLength == 2 || botHandLength == 3 || botHandLength >= 6;

  static bool shouldDrawBecauseOpponentHasTwoCards({
    required String botId,
    required int botHandLength,
    required List<String> players,
    required Map<String, int> handCounts,
  }) {
    if (shouldPlayDespiteTwoCardOpponent(botHandLength)) return false;
    return anotherPlayerHasTwoCards(
      botId: botId,
      players: players,
      handCounts: handCounts,
    );
  }

  static BotDecision decideAction({
    required bool gameStarted,
    required bool isInitialPhase,
    required int fieldNumber,
    required Suit fieldSuit,
    required String moriPhase,
    required int currentTurnIndex,
    required List<String> players,
    required String botId,
    required List<CardWidget> hand,
    required Map<String, int> handCounts,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
    required String? lastPlayerId,
    required List<String> moriDeclaredPlayerIds,
  }) {
    if (!gameStarted || fieldNumber == -1 || hand.isEmpty) {
      return const BotDecision.none();
    }
    if (moriPhase == 'mori_declared' || moriPhase == 'finished') {
      return const BotDecision.none();
    }

    // 手札1枚のときはカードを出さない（割り込みも不可）。自分のターンならドローを優先する。
    if (!isInitialPhase && hand.length == 1) {
      final drawDecision = _tryDrawDecision(
        isInitialPhase: isInitialPhase,
        handLength: hand.length,
        lastDrawerId: lastDrawerId,
        botId: botId,
        currentTurnIndex: currentTurnIndex,
        players: players,
        isDrawCompetitive: isDrawCompetitive,
      );
      if (drawDecision != null) return drawDecision;

      if (canDeclareMori(
        fieldNumber: fieldNumber,
        hand: hand,
        moriPhase: moriPhase,
        lastPlayerId: lastPlayerId,
        playerId: botId,
        moriDeclaredPlayerIds: moriDeclaredPlayerIds,
      )) {
        return const BotDecision.mori();
      }
      return const BotDecision.none();
    }

    if (canDeclareMori(
      fieldNumber: fieldNumber,
      hand: hand,
      moriPhase: moriPhase,
      lastPlayerId: lastPlayerId,
      playerId: botId,
      moriDeclaredPlayerIds: moriDeclaredPlayerIds,
    )) {
      return const BotDecision.mori();
    }

    final preferDrawForTwoCardOpponent = shouldDrawBecauseOpponentHasTwoCards(
      botId: botId,
      botHandLength: hand.length,
      players: players,
      handCounts: handCounts,
    );

    if (preferDrawForTwoCardOpponent) {
      final drawDecision = _tryDrawDecision(
        isInitialPhase: isInitialPhase,
        handLength: hand.length,
        lastDrawerId: lastDrawerId,
        botId: botId,
        currentTurnIndex: currentTurnIndex,
        players: players,
        isDrawCompetitive: isDrawCompetitive,
      );
      if (drawDecision != null) return drawDecision;
      // 通常フェーズでは割り込み（同数字）含め出さない
      if (!isInitialPhase) return const BotDecision.none();
    }

    final playIndex = _findPlayableCardIndex(
      fieldNumber: fieldNumber,
      fieldSuit: fieldSuit,
      hand: hand,
      isInitialPhase: isInitialPhase,
      currentTurnIndex: currentTurnIndex,
      players: players,
      botId: botId,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      hasPlayedThisTurn: hasPlayedThisTurn,
      excludeInterruptBecauseOpponentHasTwoCards: preferDrawForTwoCardOpponent,
    );
    if (playIndex != null) return BotDecision.play(playIndex);

    final drawDecision = _tryDrawDecision(
      isInitialPhase: isInitialPhase,
      handLength: hand.length,
      lastDrawerId: lastDrawerId,
      botId: botId,
      currentTurnIndex: currentTurnIndex,
      players: players,
      isDrawCompetitive: isDrawCompetitive,
    );
    if (drawDecision != null) return drawDecision;

    if (GameRules.mustPlayAfterSeventhDraw(
      handCount: hand.length,
      lastDrawerId: lastDrawerId,
      myId: botId,
      currentTurnIndex: currentTurnIndex,
      players: players,
    )) {
      return const BotDecision.burst();
    }

    return const BotDecision.none();
  }

  /// 相手が2枚のときは割り込み（同数字）を除外して合法手を探す
  static int? _findPlayableCardIndex({
    required int fieldNumber,
    required Suit fieldSuit,
    required List<CardWidget> hand,
    required bool isInitialPhase,
    required int currentTurnIndex,
    required List<String> players,
    required String botId,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
    required bool excludeInterruptBecauseOpponentHasTwoCards,
  }) {
    if (fieldNumber == -1 || hand.isEmpty) return null;

    final myIdx = players.indexOf(botId);
    if (myIdx < 0) return null;

    final isJokerField = GameRules.isJokerOnField(fieldNumber, fieldSuit);

    if (isInitialPhase) {
      for (var i = 0; i < hand.length; i++) {
        if (GameRules.canPlayNormal(fieldNumber, fieldSuit, hand[i], isInitialPhase: true)) {
          return i;
        }
      }
      return null;
    }

    final isServerTurn = currentTurnIndex % players.length == myIdx;
    final isLastDrawer = lastDrawerId == botId;
    final isCompetitiveParticipant = GameRules.canPlayInDrawCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: players,
      myId: botId,
    );

    for (var i = 0; i < hand.length; i++) {
      final card = hand[i];
      final isInterrupt = card.number == fieldNumber;
      if (excludeInterruptBecauseOpponentHasTwoCards && isInterrupt) continue;

      final usesTurnPlayLimit = isServerTurn || isLastDrawer || isCompetitiveParticipant;

      if (usesTurnPlayLimit && hasPlayedThisTurn && !isInterrupt && !isJokerField) {
        continue;
      }

      if (isServerTurn ||
          isLastDrawer ||
          isCompetitiveParticipant ||
          isInterrupt ||
          isJokerField) {
        if (GameRules.canPlayNormal(fieldNumber, fieldSuit, card) ||
            isInterrupt ||
            isJokerField) {
          return i;
        }
      }
    }
    return null;
  }

  static BotDecision? _tryDrawDecision({
    required bool isInitialPhase,
    required int handLength,
    required String? lastDrawerId,
    required String botId,
    required int currentTurnIndex,
    required List<String> players,
    required bool isDrawCompetitive,
  }) {
    if (isInitialPhase || !GameRules.canDraw(handLength, lastDrawerId, botId)) {
      return null;
    }
    final myIdx = players.indexOf(botId);
    if (myIdx < 0) return null;
    final isScheduledTurn = currentTurnIndex % players.length == myIdx;
    final canDrawInCompetition = GameRules.canDrawInCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: players,
      myId: botId,
      handCount: handLength,
    );
    if (isScheduledTurn || canDrawInCompetition) {
      return const BotDecision.draw();
    }
    return null;
  }

  static String actionContextKey({
    required String botId,
    required int currentTurnIndex,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required int fieldNumber,
    required Suit fieldSuit,
    required bool isInitialPhase,
    required bool hasPlayedThisTurn,
    required int handLength,
    required String moriPhase,
    required String handSignature,
    required String handCountsSignature,
    required String? lastPlayerId,
    required String? lastMoriPlayerId,
    required int moriGaeshiCount,
    required List<String> moriDeclaredPlayerIds,
  }) {
    return '$botId|$currentTurnIndex|$lastDrawerId|$isDrawCompetitive|$fieldNumber|'
        '${fieldSuit.name}|$isInitialPhase|$hasPlayedThisTurn|$handLength|$moriPhase|'
        '$lastPlayerId|$lastMoriPlayerId|$moriGaeshiCount|'
        '${moriDeclaredPlayerIds.join(",")}|$handSignature|$handCountsSignature';
  }

  static String buildHandCountsSignature(
    List<String> players,
    Map<String, int> handCounts,
  ) =>
      players.map((id) => '${id}:${handCounts[id] ?? 0}').join('|');
}
