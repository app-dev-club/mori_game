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
        sigma: 8.33,
        mu: 25,
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

    test('保存名にあなたラベルが混入していても正規化する', () {
      expect(
        PlayerDisplayName.normalizeStoredPlayerName(
          id: 'user_a',
          rawName: 'あなた（もり太郎）',
        ),
        'もり太郎',
      );
      expect(
        PlayerDisplayName.resolveForRanking(
          entry: const RankingEntry(
            id: 'user_a',
            playerName: 'あなた（もり太郎）',
            rating: 1500,
            sigma: 8.33,
            mu: 25,
            gamesPlayed: 1,
            isBot: false,
            rank: 1,
          ),
          myId: 'user_b',
          hideOpponentNames: false,
        ),
        'もり太郎',
      );
    });

    test('Bot名は slot 表記に統一する', () {
      expect(
        PlayerDisplayName.normalizeStoredPlayerName(
          id: 'bot_1',
          rawName: 'Bot一号（Bot）',
        ),
        'Bot 1',
      );
      expect(
        PlayerDisplayName.resolveForMorrieRanking(
          playerName: 'Bot一号（Bot）',
          id: 'bot_2',
          myId: 'user_a',
          hideOpponentNames: false,
        ),
        'Bot 2',
      );
    });
  });
}
