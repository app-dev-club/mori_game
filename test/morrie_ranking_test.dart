import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/morrie_rules.dart';
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

    test('Bot もランキングに含める', () {
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

      expect(entries.length, 2);
      expect(entries[0].id, 'bot_1');
      expect(entries[0].morrieBalance, 999);
      expect(entries[1].id, 'user_a');
    });

    test('空データは空リスト', () {
      expect(MorrieService.parseMorrieRankingSnapshot(null), isEmpty);
    });
  });

  group('totalMorrieForPlayers', () {
    test('人間とBotの残高を合算する', () {
      final total = MorrieService.totalMorrieForPlayers(
        const ['user_a', 'bot_1', 'user_b'],
        const {'user_a': 12, 'user_b': 8},
      );

      expect(total, 12 + MorrieRules.botFixedBalance + 8);
    });
  });
}
