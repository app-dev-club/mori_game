import 'dart:math';

import '../features/game/game_board_view.dart';
import 'bot_logic.dart';
import 'game_rules.dart';

enum SubstituteActionType { none, play, draw }

class SubstituteDecision {
  final SubstituteActionType type;
  final int? cardIndex;

  const SubstituteDecision._(this.type, [this.cardIndex]);

  const SubstituteDecision.none() : this._(SubstituteActionType.none);
  const SubstituteDecision.play(int index)
    : this._(SubstituteActionType.play, index);
  const SubstituteDecision.draw() : this._(SubstituteActionType.draw);
}

/// 離脱プレイヤーの代走。もり宣言・バーストは行わず、ドローかカード出しのみ（弱いプレイ）
class SubstituteBotLogic {
  static bool isSubstitutePlayer(String playerId, Set<String> afkPlayerIds) =>
      afkPlayerIds.contains(playerId) && !BotLogic.isBot(playerId);

  static bool shouldAct({
    required bool gameStarted,
    required bool isInitialPhase,
    required int fieldNumber,
    required String moriPhase,
    required int currentTurnIndex,
    required List<String> players,
    required String playerId,
    required List<CardWidget> hand,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
    required Suit fieldSuit,
  }) {
    if (moriPhase == 'mori_declared' || moriPhase == 'finished') return false;
    return decideAction(
          gameStarted: gameStarted,
          isInitialPhase: isInitialPhase,
          fieldNumber: fieldNumber,
          fieldSuit: fieldSuit,
          moriPhase: moriPhase,
          currentTurnIndex: currentTurnIndex,
          players: players,
          playerId: playerId,
          hand: hand,
          lastDrawerId: lastDrawerId,
          isDrawCompetitive: isDrawCompetitive,
          hasPlayedThisTurn: hasPlayedThisTurn,
        ).type !=
        SubstituteActionType.none;
  }

  static SubstituteDecision decideAction({
    required bool gameStarted,
    required bool isInitialPhase,
    required int fieldNumber,
    required Suit fieldSuit,
    required String moriPhase,
    required int currentTurnIndex,
    required List<String> players,
    required String playerId,
    required List<CardWidget> hand,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
    Random? random,
  }) {
    if (!gameStarted || fieldNumber == -1 || hand.isEmpty) {
      return const SubstituteDecision.none();
    }
    if (moriPhase == 'mori_declared' || moriPhase == 'finished') {
      return const SubstituteDecision.none();
    }

    final rng = random ?? Random();
    final myIdx = players.indexOf(playerId);
    if (myIdx < 0) return const SubstituteDecision.none();

    if (!isInitialPhase && hand.length == 1) {
      final draw = _tryDraw(
        isInitialPhase: isInitialPhase,
        handLength: hand.length,
        lastDrawerId: lastDrawerId,
        playerId: playerId,
        currentTurnIndex: currentTurnIndex,
        players: players,
        isDrawCompetitive: isDrawCompetitive,
      );
      return draw ?? const SubstituteDecision.none();
    }

    final isScheduledTurn = currentTurnIndex % players.length == myIdx;
    if (!isInitialPhase && isScheduledTurn && rng.nextBool()) {
      final draw = _tryDraw(
        isInitialPhase: isInitialPhase,
        handLength: hand.length,
        lastDrawerId: lastDrawerId,
        playerId: playerId,
        currentTurnIndex: currentTurnIndex,
        players: players,
        isDrawCompetitive: isDrawCompetitive,
      );
      if (draw != null) return draw;
    }

    final playable = _playableIndices(
      fieldNumber: fieldNumber,
      fieldSuit: fieldSuit,
      hand: hand,
      isInitialPhase: isInitialPhase,
      currentTurnIndex: currentTurnIndex,
      players: players,
      playerId: playerId,
      lastDrawerId: lastDrawerId,
      isDrawCompetitive: isDrawCompetitive,
      hasPlayedThisTurn: hasPlayedThisTurn,
    );
    if (playable.isNotEmpty) {
      return SubstituteDecision.play(playable[rng.nextInt(playable.length)]);
    }

    final draw = _tryDraw(
      isInitialPhase: isInitialPhase,
      handLength: hand.length,
      lastDrawerId: lastDrawerId,
      playerId: playerId,
      currentTurnIndex: currentTurnIndex,
      players: players,
      isDrawCompetitive: isDrawCompetitive,
    );
    return draw ?? const SubstituteDecision.none();
  }

  static List<int> _playableIndices({
    required int fieldNumber,
    required Suit fieldSuit,
    required List<CardWidget> hand,
    required bool isInitialPhase,
    required int currentTurnIndex,
    required List<String> players,
    required String playerId,
    required String? lastDrawerId,
    required bool isDrawCompetitive,
    required bool hasPlayedThisTurn,
  }) {
    if (fieldNumber == -1 || hand.isEmpty) return [];

    final myIdx = players.indexOf(playerId);
    if (myIdx < 0) return [];

    final isJokerField = GameRules.isJokerOnField(fieldNumber, fieldSuit);
    final indices = <int>[];

    if (isInitialPhase) {
      for (var i = 0; i < hand.length; i++) {
        if (GameRules.canPlayNormal(
          fieldNumber,
          fieldSuit,
          hand[i],
          isInitialPhase: true,
        )) {
          indices.add(i);
        }
      }
      return indices;
    }

    final isServerTurn = currentTurnIndex % players.length == myIdx;
    final isLastDrawer = lastDrawerId == playerId;
    final isCompetitiveParticipant = GameRules.canPlayInDrawCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: players,
      myId: playerId,
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
        if (GameRules.canPlayNormal(fieldNumber, fieldSuit, card) ||
            isInterrupt) {
          indices.add(i);
        }
      }
    }
    return indices;
  }

  static SubstituteDecision? _tryDraw({
    required bool isInitialPhase,
    required int handLength,
    required String? lastDrawerId,
    required String playerId,
    required int currentTurnIndex,
    required List<String> players,
    required bool isDrawCompetitive,
  }) {
    if (isInitialPhase ||
        !GameRules.canDraw(handLength, lastDrawerId, playerId)) {
      return null;
    }
    final myIdx = players.indexOf(playerId);
    if (myIdx < 0) return null;
    final isScheduledTurn = currentTurnIndex % players.length == myIdx;
    final canDrawInCompetition = GameRules.canDrawInCompetition(
      isDrawCompetitive: isDrawCompetitive,
      lastDrawerId: lastDrawerId,
      players: players,
      myId: playerId,
      handCount: handLength,
    );
    if (isScheduledTurn || canDrawInCompetition) {
      return const SubstituteDecision.draw();
    }
    return null;
  }
}
