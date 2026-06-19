import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/features/game/game_board_view.dart';
import 'package:mori_game/logic/bot_logic.dart';
import 'package:mori_game/logic/game_rules.dart';

void main() {
  const heart7 = CardWidget(number: 7, suit: Suit.heart);
  const spade7 = CardWidget(number: 7, suit: Suit.spade);
  const heart3 = CardWidget(number: 3, suit: Suit.heart);
  const heart4 = CardWidget(number: 4, suit: Suit.heart);
  const players = ['host', 'bot_1'];

  group('BotLogic', () {
    test('isBot は bot_ プレフィックスを判定する', () {
      expect(BotLogic.isBot('bot_123'), isTrue);
      expect(BotLogic.isBot('bot_1'), isTrue);
      expect(BotLogic.isBot('host'), isFalse);
    });

    test('tryNextBotId は bot_1, bot_2 ... bot_7 を割り当てる', () {
      expect(BotLogic.tryNextBotId([]), 'bot_1');
      expect(BotLogic.tryNextBotId(['bot_1']), 'bot_2');
      expect(BotLogic.tryNextBotId(['bot_1', 'bot_3']), 'bot_2');
      expect(BotLogic.botDisplayName('bot_2'), 'Bot 2');
    });

    test('tryNextBotId は bot_7 までで null を返す', () {
      expect(
        BotLogic.tryNextBotId([
          'bot_1',
          'bot_2',
          'bot_3',
          'bot_4',
          'bot_5',
          'bot_6',
          'bot_7',
        ]),
        isNull,
      );
    });

    test('canDeclareMori は直前に出した相手にもりできる', () {
      expect(
        BotLogic.canDeclareMori(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'none',
          lastPlayerId: 'host',
          playerId: 'bot_1',
          moriDeclaredPlayerIds: const [],
        ),
        isTrue,
      );
      expect(
        BotLogic.canDeclareMori(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'none',
          lastPlayerId: 'system',
          playerId: 'bot_1',
          moriDeclaredPlayerIds: const [],
        ),
        isFalse,
      );
    });

    test('canDeclareMori はもう宣言済みのプレイヤーは不可', () {
      expect(
        BotLogic.canDeclareMori(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'none',
          lastPlayerId: 'host',
          playerId: 'bot_1',
          moriDeclaredPlayerIds: const ['bot_1'],
        ),
        isFalse,
      );
    });

    test('canDeclareMoriGaeshi はもり宣言中に有効な手札ならもり返しできる', () {
      expect(
        BotLogic.canDeclareMoriGaeshi(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'mori_declared',
          lastMoriPlayerId: 'host',
          playerId: 'bot_1',
          moriDeclaredPlayerIds: const ['host'],
        ),
        isTrue,
      );
      expect(
        BotLogic.canDeclareMoriGaeshi(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'mori_declared',
          lastMoriPlayerId: 'bot_1',
          playerId: 'bot_1',
          moriDeclaredPlayerIds: const ['bot_1'],
        ),
        isFalse,
      );
    });

    test('canDeclareMoriGaeshi はもう宣言済みのプレイヤーは不可', () {
      expect(
        BotLogic.canDeclareMoriGaeshi(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'mori_declared',
          lastMoriPlayerId: 'host',
          playerId: 'bot_1',
          moriDeclaredPlayerIds: const ['host', 'bot_1'],
        ),
        isFalse,
      );
    });

    test('randomActionDelayMs は指定範囲内の値を返す', () {
      final random = Random(0);
      for (var i = 0; i < 20; i++) {
        final delay = BotLogic.randomActionDelayMs(
          maxMs: 10_000,
          minMs: 400,
          random: random,
        );
        expect(delay, inInclusiveRange(400, 10_000));
      }
    });

    test('decideAction はもりを最優先する', () {
      final decision = BotLogic.decideAction(
        gameStarted: true,
        isInitialPhase: false,
        fieldNumber: 7,
        fieldSuit: Suit.heart,
        moriPhase: 'none',
        currentTurnIndex: 1,
        players: players,
        botId: 'bot_1',
        hand: [heart3, heart4],
        lastDrawerId: null,
        isDrawCompetitive: false,
        hasPlayedThisTurn: false,
        lastPlayerId: 'host',
        moriDeclaredPlayerIds: const [],
      );
      expect(decision.type, BotActionType.mori);
    });

    test('decideAction は手札1枚のときドローを優先する', () {
      final decision = BotLogic.decideAction(
        gameStarted: true,
        isInitialPhase: false,
        fieldNumber: 7,
        fieldSuit: Suit.heart,
        moriPhase: 'none',
        currentTurnIndex: 1,
        players: players,
        botId: 'bot_1',
        hand: [CardWidget(number: 3, suit: Suit.club)],
        lastDrawerId: null,
        isDrawCompetitive: false,
        hasPlayedThisTurn: false,
        lastPlayerId: 'host',
        moriDeclaredPlayerIds: const [],
      );
      expect(decision.type, BotActionType.draw);
    });

    test('decideAction は手札1枚・場と同数字でも割り込み出ししない', () {
      final decision = BotLogic.decideAction(
        gameStarted: true,
        isInitialPhase: false,
        fieldNumber: 7,
        fieldSuit: Suit.heart,
        moriPhase: 'none',
        currentTurnIndex: 0,
        players: players,
        botId: 'bot_1',
        hand: [CardWidget(number: 3, suit: Suit.club)],
        lastDrawerId: null,
        isDrawCompetitive: false,
        hasPlayedThisTurn: false,
        lastPlayerId: 'host',
        moriDeclaredPlayerIds: const [],
      );
      expect(decision.type, BotActionType.none);
    });

    test('decideAction は手札1枚・相手ターンで同数字ならもりできる', () {
      final decision = BotLogic.decideAction(
        gameStarted: true,
        isInitialPhase: false,
        fieldNumber: 7,
        fieldSuit: Suit.heart,
        moriPhase: 'none',
        currentTurnIndex: 0,
        players: players,
        botId: 'bot_1',
        hand: [spade7],
        lastDrawerId: null,
        isDrawCompetitive: false,
        hasPlayedThisTurn: false,
        lastPlayerId: 'host',
        moriDeclaredPlayerIds: const [],
      );
      expect(decision.type, BotActionType.mori);
    });

    test('decideAction は手札1枚・自分のターンでは同数字でもドローする', () {
      final decision = BotLogic.decideAction(
        gameStarted: true,
        isInitialPhase: false,
        fieldNumber: 7,
        fieldSuit: Suit.heart,
        moriPhase: 'none',
        currentTurnIndex: 1,
        players: players,
        botId: 'bot_1',
        hand: [spade7],
        lastDrawerId: null,
        isDrawCompetitive: false,
        hasPlayedThisTurn: false,
        lastPlayerId: 'host',
        moriDeclaredPlayerIds: const [],
      );
      expect(decision.type, BotActionType.draw);
    });

    test('decideAction は合法手があれば出す', () {
      final decision = BotLogic.decideAction(
        gameStarted: true,
        isInitialPhase: false,
        fieldNumber: 7,
        fieldSuit: Suit.heart,
        moriPhase: 'none',
        currentTurnIndex: 1,
        players: players,
        botId: 'bot_1',
        hand: [spade7, CardWidget(number: 3, suit: Suit.club)],
        lastDrawerId: null,
        isDrawCompetitive: false,
        hasPlayedThisTurn: false,
        lastPlayerId: 'bot_1',
        moriDeclaredPlayerIds: const [],
      );
      expect(decision.type, BotActionType.play);
      expect(decision.cardIndex, 0);
    });
  });
}
