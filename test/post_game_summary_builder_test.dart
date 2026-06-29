import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/post_game_summary_builder.dart';

void main() {
  group('PostGameSummaryBuilder', () {
    test('モリー列は累計ポイント×レートを表示する', () {
      final summary = PostGameSummaryBuilder.build(
        roster: const ['a', 'b'],
        names: const {'a': 'Alice', 'b': 'Bob'},
        playerPoints: const {'a': 12, 'b': -12},
        lastMatchPointDeltas: const {'a': 6, 'b': -6},
        seriesRatingDetails: const {},
        seriesMorrieDetails: const {},
        lastMatchMorrieDeltas: const {'a': 999, 'b': -999},
        lastMatchMorrieBalances: const {'a': 20, 'b': 5},
        morrieRate: 5,
        totalMatches: 3,
        completedMatches: 1,
        seriesComplete: false,
      );

      expect(summary.showMorrie, isTrue);
      expect(summary.players[0].morrieDelta, 60);
      expect(summary.players[1].morrieDelta, -60);
    });

    test('モリーレート0のときモリー列を非表示', () {
      final summary = PostGameSummaryBuilder.build(
        roster: const ['a'],
        names: const {'a': 'Alice'},
        playerPoints: const {'a': 10},
        lastMatchPointDeltas: const {'a': 10},
        seriesRatingDetails: const {},
        seriesMorrieDetails: const {},
        lastMatchMorrieDeltas: const {},
        lastMatchMorrieBalances: const {},
        morrieRate: 0,
        totalMatches: 1,
        completedMatches: 1,
        seriesComplete: true,
      );

      expect(summary.showMorrie, isFalse);
    });
    test('Bot飛び回復後の残高は回復済みとしてマークする', () {
      final summary = PostGameSummaryBuilder.build(
        roster: const ['human', 'bot_1'],
        names: const {'human': 'Alice', 'bot_1': 'Bot'},
        playerPoints: const {'human': 6, 'bot_1': -6},
        lastMatchPointDeltas: const {'human': 6, 'bot_1': -6},
        seriesRatingDetails: const {},
        seriesMorrieDetails: const {},
        lastMatchMorrieDeltas: const {'human': 6, 'bot_1': -6},
        lastMatchMorrieBalances: const {'human': 16, 'bot_1': 5},
        currentMorrieBalances: const {'human': 16, 'bot_1': 5},
        morrieBurstPlayerId: 'bot_1',
        morrieBurstRecoveryApplied: true,
        morrieRate: 1,
        totalMatches: 1,
        completedMatches: 1,
        seriesComplete: true,
      );

      expect(summary.showsRecoveredMorrieBalance, isTrue);
      final botRow = summary.players.firstWhere((r) => r.name == 'Bot');
      expect(botRow.morrieBalance, 5);
      expect(botRow.morrieBalanceIsRecovered, isTrue);
    });
  });
}
