import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/room_lifecycle.dart';

void main() {
  group('RoomLifecycle.shouldAutoDeleteRoom', () {
    const now = 1_700_000_000_000;

    Map<String, dynamic> baseRoom({List<String>? players, bool gameStarted = false}) => {
          'createdAt': now,
          'players': players ?? ['host'],
          'roomStatus': gameStarted ? 'closed' : 'open',
          'gameStarted': gameStarted,
        };

    test('対戦中（gameStarted + roomStatus closed）は削除しない', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          baseRoom(gameStarted: true),
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
          {'createdAt': now, 'players': []},
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
