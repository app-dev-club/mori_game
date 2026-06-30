import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/features/game/game_board_view.dart';
import 'package:mori_game/logic/substitute_bot_logic.dart';

void main() {
  group('SubstituteBotLogic', () {
    test('skips joker on joker field', () {
      final decision = SubstituteBotLogic.decideAction(
        gameStarted: true,
        isInitialPhase: false,
        fieldNumber: 0,
        fieldSuit: Suit.joker,
        moriPhase: 'none',
        currentTurnIndex: 0,
        players: const ['p1', 'p2'],
        playerId: 'p1',
        hand: const [
          CardWidget(number: 0, suit: Suit.joker),
          CardWidget(number: 5, suit: Suit.heart),
        ],
        lastDrawerId: null,
        isDrawCompetitive: false,
        hasPlayedThisTurn: false,
        random: Random(0),
      );

      expect(decision.type, SubstituteActionType.play);
      expect(decision.cardIndex, 1);
    });

    test('never returns mori or burst actions', () {
      final hand = [
        const CardWidget(number: 5, suit: Suit.spade),
        const CardWidget(number: 7, suit: Suit.heart),
      ];
      final decision = SubstituteBotLogic.decideAction(
        gameStarted: true,
        isInitialPhase: false,
        fieldNumber: 5,
        fieldSuit: Suit.club,
        moriPhase: 'none',
        currentTurnIndex: 0,
        players: const ['p1', 'p2'],
        playerId: 'p1',
        hand: hand,
        lastDrawerId: null,
        isDrawCompetitive: false,
        hasPlayedThisTurn: false,
        random: Random(0),
      );
      expect(decision.type, isNot(SubstituteActionType.none));
      expect(
        decision.type == SubstituteActionType.play ||
            decision.type == SubstituteActionType.draw,
        isTrue,
      );
    });

    test('does not act during mori_declared phase', () {
      final hand = [const CardWidget(number: 5, suit: Suit.spade)];
      expect(
        SubstituteBotLogic.shouldAct(
          gameStarted: true,
          isInitialPhase: false,
          fieldNumber: 5,
          moriPhase: 'mori_declared',
          currentTurnIndex: 0,
          players: const ['p1'],
          playerId: 'p1',
          hand: hand,
          lastDrawerId: null,
          isDrawCompetitive: false,
          hasPlayedThisTurn: false,
          fieldSuit: Suit.club,
        ),
        isFalse,
      );
    });
  });
}
