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
  });
}
