import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/features/game/game_board_view.dart';
import 'package:mori_game/logic/game_rules.dart';

void main() {
  const heart7 = CardWidget(number: 7, suit: Suit.heart);
  const spade7 = CardWidget(number: 7, suit: Suit.spade);
  const heart5 = CardWidget(number: 5, suit: Suit.heart);
  const joker = CardWidget(number: 0, suit: Suit.joker);

  group('canPlayNormal', () {
    test('山札をめくる前は手札から出せない', () {
      expect(
        GameRules.canPlayNormal(-1, Suit.joker, heart7),
        isFalse,
      );
    });

    test('初期フェーズは同じ数字のみ出せる', () {
      expect(
        GameRules.canPlayNormal(7, Suit.heart, spade7, isInitialPhase: true),
        isTrue,
      );
      expect(
        GameRules.canPlayNormal(7, Suit.heart, heart5, isInitialPhase: true),
        isFalse,
      );
    });

    test('通常フェーズは同じ数字または同じスートで出せる', () {
      expect(GameRules.canPlayNormal(7, Suit.heart, spade7), isTrue);
      expect(GameRules.canPlayNormal(7, Suit.heart, heart5), isTrue);
      expect(GameRules.canPlayNormal(7, Suit.heart, CardWidget(number: 5, suit: Suit.spade)), isFalse);
    });

    test('ジョーカー場では任意のカードを出せる', () {
      expect(GameRules.canPlayNormal(0, Suit.joker, heart5), isTrue);
      expect(GameRules.canPlayNormal(0, Suit.joker, heart5, isInitialPhase: true), isTrue);
    });

    test('未めくりプレースホルダーはジョーカー場とみなさない', () {
      expect(GameRules.isJokerOnField(-1, Suit.joker), isFalse);
      expect(GameRules.isJokerOnField(0, Suit.joker), isTrue);
    });
  });

  group('canDeclareMori', () {
    const heart3 = CardWidget(number: 3, suit: Suit.heart);
    const heart4 = CardWidget(number: 4, suit: Suit.heart);

    test('相手が出したカードに対してもりできる', () {
      expect(
        GameRules.canDeclareMori(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'none',
          lastPlayerId: 'host',
          playerId: 'guest',
          moriDeclaredPlayerIds: const [],
        ),
        isTrue,
      );
    });

    test('山札めくり（system）に対してもりできない', () {
      expect(
        GameRules.canDeclareMori(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'none',
          lastPlayerId: 'system',
          playerId: 'guest',
          moriDeclaredPlayerIds: const [],
        ),
        isFalse,
      );
    });

    test('自分が出したカードに対してもりできない', () {
      expect(
        GameRules.canDeclareMori(
          fieldNumber: 7,
          hand: [heart3, heart4],
          moriPhase: 'none',
          lastPlayerId: 'guest',
          playerId: 'guest',
          moriDeclaredPlayerIds: const [],
        ),
        isFalse,
      );
    });
  });

  group('auto play', () {
    const players = ['host', 'guest'];

    test('shouldAutoPlayOnTimeout はドロー可能な自分のターンのみ true', () {
      expect(
        GameRules.shouldAutoPlayOnTimeout(
          gameStarted: true,
          isInitialPhase: false,
          fieldNumber: 7,
          moriPhase: 'none',
          currentTurnIndex: 1,
          players: players,
          myId: 'guest',
          handCount: 5,
          lastDrawerId: null,
          isDrawCompetitive: false,
        ),
        isTrue,
      );
      expect(
        GameRules.shouldAutoPlayOnTimeout(
          gameStarted: true,
          isInitialPhase: false,
          fieldNumber: 7,
          moriPhase: 'none',
          currentTurnIndex: 0,
          players: players,
          myId: 'guest',
          handCount: 5,
          lastDrawerId: null,
          isDrawCompetitive: false,
        ),
        isFalse,
      );
      expect(
        GameRules.shouldAutoPlayOnTimeout(
          gameStarted: true,
          isInitialPhase: true,
          fieldNumber: 7,
          moriPhase: 'none',
          currentTurnIndex: 1,
          players: players,
          myId: 'guest',
          handCount: 5,
          lastDrawerId: null,
          isDrawCompetitive: false,
        ),
        isFalse,
      );
    });

    test('7枚目を引いた後も自動プレイ対象', () {
      expect(
        GameRules.shouldAutoPlayOnTimeout(
          gameStarted: true,
          isInitialPhase: false,
          fieldNumber: 7,
          moriPhase: 'none',
          currentTurnIndex: 1,
          players: players,
          myId: 'guest',
          handCount: 7,
          lastDrawerId: 'guest',
          isDrawCompetitive: false,
        ),
        isTrue,
      );
    });

    test('findPlayableCardIndex は合法手を返し、無ければ null', () {
      final hand = [heart7, heart5, CardWidget(number: 3, suit: Suit.spade)];

      expect(
        GameRules.findPlayableCardIndex(
          fieldNumber: 7,
          fieldSuit: Suit.heart,
          hand: hand,
          isInitialPhase: false,
          currentTurnIndex: 1,
          players: players,
          myId: 'guest',
          lastDrawerId: null,
          isDrawCompetitive: false,
          hasPlayedThisTurn: false,
        ),
        0,
      );

      expect(
        GameRules.findPlayableCardIndex(
          fieldNumber: 7,
          fieldSuit: Suit.heart,
          hand: [CardWidget(number: 3, suit: Suit.spade), CardWidget(number: 4, suit: Suit.club)],
          isInitialPhase: false,
          currentTurnIndex: 1,
          players: players,
          myId: 'guest',
          lastDrawerId: null,
          isDrawCompetitive: false,
          hasPlayedThisTurn: false,
        ),
        isNull,
      );
    });
    test('shouldStartInitialPhaseAutoFlip は初期フェーズで場にカードがあるとき true', () {
      expect(
        GameRules.shouldStartInitialPhaseAutoFlip(
          isInitialPhase: true,
          fieldNumber: 7,
          moriPhase: 'none',
          gameStarted: true,
        ),
        isTrue,
      );
      expect(
        GameRules.shouldStartInitialPhaseAutoFlip(
          isInitialPhase: true,
          fieldNumber: -1,
          moriPhase: 'none',
          gameStarted: true,
        ),
        isFalse,
      );
      expect(
        GameRules.shouldStartInitialPhaseAutoFlip(
          isInitialPhase: false,
          fieldNumber: 7,
          moriPhase: 'none',
          gameStarted: true,
        ),
        isFalse,
      );
    });
  });
}
