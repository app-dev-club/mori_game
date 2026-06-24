import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/services/morrie_service.dart';

void main() {
  group('parseMorrieRankingSnapshot', () {
    test('モリー残高降順に順位付けする', () {
      final entries = MorrieService.parseMorrieRankingSnapshot({
        'user_a': {
          'morrieBalance': 25,
          'playerName': 'Alice',
        },
        'user_b': {
          'morrieBalance': 40,
          'playerName': 'Bob',
        },
        'user_c': {
          'morrieBalance': 10,
          'playerName': 'Carol',
        },
      });

      expect(entries.length, 3);
      expect(entries[0].rank, 1);
      expect(entries[0].playerName, 'Bob');
      expect(entries[0].morrieBalance, 40);
      expect(entries[1].playerName, 'Alice');
      expect(entries[2].playerName, 'Carol');
    });

    test('Bot ID はランキングに含めない', () {
      final entries = MorrieService.parseMorrieRankingSnapshot({
        'user_a': {
          'morrieBalance': 20,
          'playerName': 'Alice',
        },
        'bot_1': {
          'morrieBalance': 999,
          'playerName': 'Bot 1',
        },
      });

      expect(entries.length, 1);
      expect(entries.single.id, 'user_a');
    });

    test('空データは空リスト', () {
      expect(MorrieService.parseMorrieRankingSnapshot(null), isEmpty);
    });
  });
}
