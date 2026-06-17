import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/services/rating_service.dart';

void main() {
  group('parseRankingSnapshot', () {
    test('レート降順に順位付けする', () {
      final entries = RatingService.parseRankingSnapshot({
        'user_a': {'rating': 1600, 'gamesPlayed': 3, 'playerName': 'Alice', 'isBot': false},
        'bot_1': {'rating': 1500, 'gamesPlayed': 5, 'isBot': true},
        'user_b': {'rating': 1700, 'gamesPlayed': 1, 'playerName': 'Bob', 'isBot': false},
      });

      expect(entries.length, 3);
      expect(entries[0].rank, 1);
      expect(entries[0].playerName, 'Bob');
      expect(entries[0].rating, 1700);
      expect(entries[1].playerName, 'Alice');
      expect(entries[2].playerName, 'Bot 1');
      expect(entries[2].isBot, isTrue);
    });

    test('空データは空リスト', () {
      expect(RatingService.parseRankingSnapshot(null), isEmpty);
    });
  });

  group('resolvePlayerName', () {
    test('playerName を優先する', () {
      expect(
        RatingService.resolvePlayerName('uid1', {
          'playerName': 'もり太郎',
          'displayName': 'mori_taro',
        }),
        'もり太郎',
      );
    });

    test('Bot は Bot 表示名', () {
      expect(
        RatingService.resolvePlayerName('bot_2', {'isBot': true, 'rating': 1500}),
        'Bot 2',
      );
    });
  });
}
