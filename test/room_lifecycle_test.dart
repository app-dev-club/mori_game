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

  group('RoomLifecycle.isGameFullyConcluded', () {
    const now = 1_700_000_000_000;

    test('シリーズ途中で次戦未スケジュールのときは終了扱いにしない', () {
      expect(
        RoomLifecycle.isGameFullyConcluded(
          {
            'gameStarted': true,
            'moriPhase': 'finished',
            'totalMatches': 3,
            'completedMatches': 0,
          },
          nowMs: now,
        ),
        isFalse,
      );
      expect(
        RoomLifecycle.isGameFullyConcluded(
          {
            'gameStarted': true,
            'moriPhase': 'finished',
            'postGameActive': true,
            'totalMatches': 3,
            'completedMatches': 1,
            'seriesNextMatchAt': now + 5000,
          },
          nowMs: now,
        ),
        isFalse,
      );
    });

    test('次戦開始猶予を過ぎたら終了扱い', () {
      expect(
        RoomLifecycle.isGameFullyConcluded(
          {
            'gameStarted': true,
            'moriPhase': 'finished',
            'totalMatches': 3,
            'completedMatches': 1,
            'seriesNextMatchAt': now - RoomLifecycle.seriesContinueGraceMs - 1,
          },
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('1戦のみは completedMatches が揃えば終了扱い', () {
      expect(
        RoomLifecycle.isGameFullyConcluded(
          {
            'gameStarted': true,
            'moriPhase': 'finished',
            'totalMatches': 1,
            'completedMatches': 0,
          },
          nowMs: now,
        ),
        isFalse,
      );
      expect(
        RoomLifecycle.isGameFullyConcluded(
          {
            'gameStarted': true,
            'moriPhase': 'finished',
            'totalMatches': 1,
            'completedMatches': 1,
            'postGameEndedAt': now - 120_000,
          },
          nowMs: now,
        ),
        isTrue,
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
            'createdAt': now - RoomLifecycle.newRoomGraceMs - 1,
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

    test('作成直後（presence 登録前）は削除しない', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now - 5_000,
            'players': ['host'],
            'presence': {},
            'roomStatus': 'open',
            'gameStarted': false,
          },
          nowMs: now,
        ),
        isFalse,
      );
    });

    test('presence 未導入の open 待機ロビー（players のみ）は削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now - RoomLifecycle.newRoomGraceMs - 1,
            'players': ['host'],
            'roomStatus': 'open',
            'gameStarted': false,
          },
          nowMs: now,
        ),
        isTrue,
      );
    });

    test('presence 未導入の対戦中ゴーストルームは維持する（復帰用）', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host', 'guest'],
            'roomStatus': 'closed',
            'gameStarted': true,
            'moriPhase': 'none',
          },
          nowMs: now,
        ),
        isFalse,
      );
    });

    test('対戦中で全員切断（presence 空）でも進行中なら維持する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host', 'guest'],
            'presence': {},
            'gameStarted': true,
            'roomStatus': 'closed',
            'moriPhase': 'none',
          },
          nowMs: now,
        ),
        isFalse,
      );
    });

    test('終了済み対戦ルームは削除する', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host', 'guest'],
            'presence': {},
            'gameStarted': true,
            'moriPhase': 'finished',
            'completedMatches': 1,
            'totalMatches': 1,
            'postGameEndedAt': now - 120_000,
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

    test('観戦のみの進行中ルームは削除しない', () {
      expect(
        RoomLifecycle.shouldAutoDeleteRoom(
          {
            'createdAt': now,
            'players': ['host', 'guest'],
            'presence': {},
            'afkPlayerIds': {'host': true, 'guest': true},
            'spectators': {'spec1': '観戦者'},
            'gameStarted': true,
            'moriPhase': 'none',
            'totalMatches': 3,
            'completedMatches': 0,
          },
          nowMs: now,
        ),
        isFalse,
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

  group('RoomLifecycle lobby & automation', () {
    const timestamp = 1700000000000;

    test('isVisibleInPublicLobby shows in-progress rooms without presence', () {
      expect(
        RoomLifecycle.isVisibleInPublicLobby({
          'isPrivate': false,
          'gameStarted': true,
          'players': ['u1', 'bot_1'],
          'presence': {},
          'moriPhase': 'none',
        }),
        isTrue,
      );
    });

    test('isVisibleInPublicLobby hides concluded games', () {
      expect(
        RoomLifecycle.isVisibleInPublicLobby({
          'isPrivate': false,
          'gameStarted': true,
          'players': ['u1'],
          'moriPhase': 'finished',
          'completedMatches': 1,
          'totalMatches': 1,
          'postGameEndedAt': timestamp - 120_000,
        }),
        isFalse,
      );
    });

    test('needsBackgroundAutomation when only bots and afk humans remain', () {
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'players': ['u1', 'bot_1'],
          'presence': {},
          'afkPlayerIds': {'u1': true},
          'moriPhase': 'none',
        }),
        isTrue,
      );
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'players': ['bot_1', 'bot_2'],
          'presence': {},
          'moriPhase': 'none',
        }),
        isTrue,
      );
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'players': ['u1', 'u2'],
          'presence': {},
          'afkPlayerIds': {'u1': true, 'u2': true},
          'moriPhase': 'none',
        }),
        isTrue,
      );
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'players': ['u1', 'u2'],
          'presence': {},
          'moriPhase': 'none',
        }),
        isFalse,
      );
    });

    test('needsBackgroundAutomation is false when a human is connected', () {
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'players': ['u1', 'bot_1'],
          'presence': {'u1': timestamp},
          'afkPlayerIds': {},
          'moriPhase': 'none',
        }),
        isFalse,
      );
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'host': 'host',
          'players': ['host', 'guest'],
          'presence': {'guest': timestamp},
          'afkPlayerIds': {'host': true},
          'moriPhase': 'none',
        }),
        isFalse,
      );
    });

    test('needsBackgroundAutomation stays true during series continuation', () {
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'players': ['u1', 'u2'],
          'presence': {},
          'afkPlayerIds': {'u1': true, 'u2': true},
          'moriPhase': 'finished',
          'postGameActive': true,
          'completedMatches': 1,
          'totalMatches': 3,
          'seriesNextMatchAt': timestamp + 5000,
        }),
        isTrue,
      );
    });

    test('needsPostGameSteward when match ended and no one connected', () {
      expect(
        RoomLifecycle.needsPostGameSteward({
          'gameStarted': true,
          'moriPhase': 'finished',
          'players': ['u1', 'bot_1'],
          'presence': {},
          'afkPlayerIds': {'u1': true},
          'completedMatches': 1,
          'totalMatches': 1,
        }),
        isTrue,
      );
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'moriPhase': 'finished',
          'players': ['u1', 'bot_1'],
          'presence': {},
          'afkPlayerIds': {'u1': true},
          'completedMatches': 3,
          'totalMatches': 3,
          'seriesRatingApplied': true,
          'seriesMorrieSettled': true,
        }),
        isTrue,
      );
    });

    test('needsPostGameSteward is false when a human is connected', () {
      expect(
        RoomLifecycle.needsPostGameSteward({
          'gameStarted': true,
          'moriPhase': 'finished',
          'players': ['u1'],
          'presence': {'u1': timestamp},
        }),
        isFalse,
      );
    });

    test('needsBackgroundAutomation is false during active gameplay with connected human', () {
      expect(
        RoomLifecycle.needsBackgroundAutomation({
          'gameStarted': true,
          'players': ['u1', 'u2'],
          'presence': {'u1': timestamp},
          'moriPhase': 'none',
        }),
        isFalse,
      );
    });
  });
}
