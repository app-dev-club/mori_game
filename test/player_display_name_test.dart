import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/player_display_name.dart';
import 'package:mori_game/models/ranking_entry.dart';

void main() {
  const playerIds = ['host', 'guest', 'bot_1'];
  const playerNames = {
    'host': 'ホスト太郎',
    'guest': 'ゲスト次郎',
    'bot_1': 'Bot一号',
  };

  group('PlayerDisplayName', () {
    test('自分の名前は常に表示する', () {
      expect(
        PlayerDisplayName.resolve(
          playerId: 'guest',
          playerIds: playerIds,
          myId: 'guest',
          playerNames: playerNames,
          hideOpponentNames: true,
        ),
        'あなた（ゲスト次郎）',
      );
    });

    test('相手名を隠すと席番号になる', () {
      expect(
        PlayerDisplayName.resolve(
          playerId: 'host',
          playerIds: playerIds,
          myId: 'guest',
          playerNames: playerNames,
          hostId: 'host',
          hideOpponentNames: true,
        ),
        'プレイヤー1（ホスト）',
      );
    });

    test('相手名を表示するときは登録名を使う', () {
      expect(
        PlayerDisplayName.resolve(
          playerId: 'host',
          playerIds: playerIds,
          myId: 'guest',
          playerNames: playerNames,
          hostId: 'host',
          hideOpponentNames: false,
        ),
        'ホスト太郎（ホスト）',
      );
    });

    test('レーティング用は実名を優先する', () {
      expect(
        PlayerDisplayName.resolveForRating(
          playerId: 'guest',
          playerIds: playerIds,
          playerNames: playerNames,
        ),
        'ゲスト次郎',
      );
    });

    test('ランキングは自分以外を匿名化できる', () {
      const entry = RankingEntry(
        id: 'host',
        playerName: 'ホスト太郎',
        rating: 1500,
        gamesPlayed: 3,
        isBot: false,
        rank: 1,
      );
      expect(
        PlayerDisplayName.resolveForRanking(
          entry: entry,
          myId: 'guest',
          hideOpponentNames: true,
        ),
        '---',
      );
      expect(
        PlayerDisplayName.resolveForRanking(
          entry: entry,
          myId: 'guest',
          hideOpponentNames: false,
        ),
        'ホスト太郎',
      );
    });
  });
}
