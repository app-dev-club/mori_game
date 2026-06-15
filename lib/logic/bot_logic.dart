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

  static bool isBot(String playerId) => playerId.startsWith(idPrefix);

  static String nextBotName(Iterable<String> playerIds) {
    final count = playerIds.where(isBot).length + 1;
    return 'Bot $count';
  }

  static bool canDeclareMori({
    required int fieldNumber,
    required List<CardWidget> hand,
    required String moriPhase,
    required String? lastPlayerId,
    required String playerId,
  }) {
    if (moriPhase != 'none' || fieldNumber == -1) return false;
    if (lastPlayerId == null || lastPlayerId == playerId || lastPlayerId == 'system') {
      return false;
    }
    return GameRules.isValidMori(fieldNumber, hand);
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
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
    required Suit fieldSuit,
    required String? lastPlayerId,
  }) {
    if (!gameStarted || fieldNumber == -1) return false;
    if (moriPhase == 'mori_declared' || moriPhase == 'finished') return false;
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
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      hasPlayedThisTurn: hasPlayedThisTurn,
      lastPlayerId: lastPlayerId,
    ).type != BotActionType.none;
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
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
    required String? lastPlayerId,
  }) {
    if (!gameStarted || fieldNumber == -1 || hand.isEmpty) {
      return const BotDecision.none();
    }
    if (moriPhase == 'mori_declared' || moriPhase == 'finished') {
      return const BotDecision.none();
    }

    if (canDeclareMori(
      fieldNumber: fieldNumber,
      hand: hand,
      moriPhase: moriPhase,
      lastPlayerId: lastPlayerId,
      playerId: botId,
    )) {
      return const BotDecision.mori();
    }

    // 手札1枚のときはカードを出さずドローを優先（初期フェーズはドロー不可のため除く）
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
    }

    final playIndex = GameRules.findPlayableCardIndex(
      fieldNumber: fieldNumber,
      fieldSuit: fieldSuit,
      hand: hand,
      isInitialPhase: isInitialPhase,
      currentTurnIndex: currentTurnIndex,
      players: players,
      myId: botId,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      hasPlayedThisTurn: hasPlayedThisTurn,
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
    required String? lastPlayerId,
  }) {
    return '$botId|$currentTurnIndex|$lastDrawerId|$isDrawCompetitive|$fieldNumber|'
        '${fieldSuit.name}|$isInitialPhase|$hasPlayedThisTurn|$handLength|$moriPhase|'
        '$lastPlayerId|$handSignature';
  }
}
