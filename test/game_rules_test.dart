import 'dart:math';

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

  group('canOpenJoker', () {
    test('ジョーカー所持かつ未公開なら可能', () {
      expect(
        GameRules.canOpenJoker(
          hand: [joker, heart5],
          playerId: 'guest',
          openJokerPlayerIds: const {},
          gameStarted: true,
          moriPhase: 'none',
        ),
        isTrue,
      );
    });

    test('公開済みなら不可', () {
      expect(
        GameRules.canOpenJoker(
          hand: [joker, heart5],
          playerId: 'guest',
          openJokerPlayerIds: const {'guest'},
          gameStarted: true,
          moriPhase: 'none',
        ),
        isFalse,
      );
    });

    test('もり宣言中は不可', () {
      expect(
        GameRules.canOpenJoker(
          hand: [joker, heart5],
          playerId: 'guest',
          openJokerPlayerIds: const {},
          gameStarted: true,
          moriPhase: 'mori_declared',
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

  group('opponentsClockwiseFrom', () {
    const ids = ['host', 'guest1', 'guest2'];

    test('自分の次の手番から時計回りに並べる', () {
      expect(GameRules.opponentsClockwiseFrom('host', ids), ['guest1', 'guest2']);
      expect(GameRules.opponentsClockwiseFrom('guest1', ids), ['guest2', 'host']);
      expect(GameRules.opponentsClockwiseFrom('guest2', ids), ['host', 'guest1']);
    });

    test('index 付きエントリは手番判定に使える', () {
      final entries = GameRules.opponentEntriesClockwiseFrom('guest1', ids);
      expect(entries.map((e) => e.key).toList(), [2, 0]);
      expect(entries.map((e) => e.value).toList(), ['guest2', 'host']);
    });
  });

  group('shuffledPlayerOrder', () {
    test('メンバーは変えず順序だけ入れ替える', () {
      const ids = ['a', 'b', 'c', 'd'];
      final shuffled = GameRules.shuffledPlayerOrder(ids, Random(42));
      expect(shuffled.toSet(), ids.toSet());
      expect(shuffled.length, ids.length);
      expect(shuffled, isNot(equals(ids)));
    });
  });
}
