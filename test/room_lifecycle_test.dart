import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/room_lifecycle.dart';

void main() {
  group('RoomLifecycle.hasActivePlayers', () {
    test('presence が空なら接続プレイヤーなし', () {
      expect(
        RoomLifecycle.hasActivePlayers({'presence': {}, 'players': ['host']}),
        isFalse,
      );
    });

    test('presence にエントリがあれば接続プレイヤーあり', () {
      expect(
        RoomLifecycle.hasActivePlayers({'presence': {'p1': 1}, 'players': ['p1']}),
        isTrue,
      );
    });

    test('presence 未導入の古いルームは players を参照しない', () {
      expect(
        RoomLifecycle.hasActivePlayers({'players': ['host']}),
        isFalse,
      );
      expect(
        RoomLifecycle.hasActivePlayers({'players': []}),
        isFalse,
      );
    });
  });

  group('RoomLifecycle.shouldAutoDeleteRoom', () {
    const now = 1_700_000_000_000;

    Map<String, dynamic> baseRoom({List<String>? players, bool gameStarted = false}) => {
          'createdAt': now,
          'players': players ?? ['host'],
          'presence': {players?.first ?? 'host': now},
          'roomStatus': gameStarted ? 'closed' : 'open',
          'gameStarted': gameStarted,
        };

    test('対戦中（接続プレイヤーあり）は削除しない', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host', 'guest'],
            'presence': {'host': now, 'guest': now},
            'roomStatus': 'closed',
            'gameStarted': true,
          },
          nowMs: now,
        ),
        isFalse,
      );
    });

    test('プレイヤーがいる待機ロビーは削除しない', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host', 'guest'],
            'presence': {'host': now, 'guest': now},
            'roomStatus': 'closed',
            'gameStarted': false,
          },
          nowMs: now,
        ),
        isFalse,
      );
    });

    test('プレイヤー不在の空ルームは削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {'createdAt': now, 'players': [], 'presence': {}},
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('presence が空で players に stale ID が残っていても削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host'],
            'presence': {},
            'roomStatus': 'closed',
            'gameStarted': false,
          },
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('presence 未導入の open 待機ロビー（players のみ）は削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host'],
            'roomStatus': 'open',
            'gameStarted': false,
          },
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('presence 未導入の対戦中ゴーストルームは削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host', 'guest'],
            'roomStatus': 'closed',
            'gameStarted': true,
          },
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('対戦中でも全員切断（presence 空）なら削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host', 'guest'],
            'presence': {},
            'gameStarted': true,
            'roomStatus': 'closed',
          },
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('stale な presence だけ残る放置待機ロビーは削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now - RoomLifecycle.inactiveLobbyAgeMs - 1,
            'players': ['host'],
            'presence': {'host': now - RoomLifecycle.inactiveLobbyAgeMs - 1},
            'roomStatus': 'open',
            'gameStarted': false,
          },
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('24時間以上経過したルームは削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          baseRoom(gameStarted: true),
          nowMs: now + RoomLifecycle.maxRoomAgeMs + 1,
        ),
        isTrue,
      );
    });

    test('試合後オーバーレイ中は削除しない', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            ...baseRoom(gameStarted: false),
            'postGameActive': true,
            'roomStatus': 'closed',
          },
          nowMs: now,
        ),
        isFalse,
      );
    });
  });
}
