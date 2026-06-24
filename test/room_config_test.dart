import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/room_config.dart';

void main() {
  group('RoomConfig', () {
    test('resolveMaxPlayers は未設定時に absoluteMaxPlayers を返す', () {
      expect(RoomConfig.resolveMaxPlayers(null), RoomConfig.absoluteMaxPlayers);
    });

    test('resolveMaxPlayers は有効な値をそのまま返す', () {
      expect(RoomConfig.resolveMaxPlayers(4), 4);
    });

    test('isRoomFull は定員到達を判定する', () {
      expect(RoomConfig.isRoomFull(3, 4), isFalse);
      expect(RoomConfig.isRoomFull(4, 4), isTrue);
      expect(RoomConfig.isRoomFull(5, 4), isTrue);
    });

    test('resolveMatchCount は Firebase の num でも対戦回数を解決する', () {
      expect(RoomConfig.resolveMatchCount(3), 3);
      expect(RoomConfig.resolveMatchCount(3.0), 3);
      expect(RoomConfig.resolveMatchCount(null), RoomConfig.defaultMatchCount);
    });

    test('resolveTurnTimeoutSeconds は持ち時間を解決する', () {
      expect(RoomConfig.resolveTurnTimeoutSeconds(15), 15);
      expect(RoomConfig.resolveTurnTimeoutSeconds(15.0), 15);
      expect(RoomConfig.resolveTurnTimeoutSeconds(null), RoomConfig.defaultTurnTimeoutSeconds);
      expect(RoomConfig.resolveTurnTimeoutSeconds(2), RoomConfig.defaultTurnTimeoutSeconds);
      expect(RoomConfig.resolveTurnTimeoutSeconds(121), RoomConfig.defaultTurnTimeoutSeconds);
    });

    test('resolveMorrieRate は1以上の整数を解決する', () {
      expect(RoomConfig.resolveMorrieRate(10), 10);
      expect(RoomConfig.resolveMorrieRate(0), RoomConfig.defaultMorrieRate);
      expect(RoomConfig.resolveMorrieRate(null), RoomConfig.defaultMorrieRate);
    });

    test('parseMorrieRateInput は1以上の整数のみ受け付ける', () {
      expect(RoomConfig.parseMorrieRateInput('10'), 10);
      expect(RoomConfig.parseMorrieRateInput('1'), 1);
      expect(RoomConfig.parseMorrieRateInput('0'), isNull);
      expect(RoomConfig.parseMorrieRateInput('abc'), isNull);
    });

    test('resolveMinMorrieBalance と meetsMinMorrieRequirement', () {
      expect(RoomConfig.resolveMinMorrieBalance(10), 10);
      expect(RoomConfig.resolveMinMorrieBalance(null), 0);
      expect(RoomConfig.resolveMinMorrieBalance(0), 0);
      expect(RoomConfig.meetsMinMorrieRequirement(10, 0), isTrue);
      expect(RoomConfig.meetsMinMorrieRequirement(10, 10), isTrue);
      expect(RoomConfig.meetsMinMorrieRequirement(9, 10), isFalse);
    });

    test('parseMinMorrieBalanceInput は0以上の整数のみ受け付ける', () {
      expect(RoomConfig.parseMinMorrieBalanceInput('0'), 0);
      expect(RoomConfig.parseMinMorrieBalanceInput('25'), 25);
      expect(RoomConfig.parseMinMorrieBalanceInput('-1'), isNull);
      expect(RoomConfig.parseMinMorrieBalanceInput(''), isNull);
    });

    test('canUserSpectateRoom は接続中の参加者のみ観戦不可', () {
      const uid = 'user1';
      const other = 'user2';
      final connectedHostRoom = {
        'host': uid,
        'players': [uid, other],
        'presence': {uid: 1, other: 1},
      };
      final connectedGuestRoom = {
        'host': other,
        'players': [uid, other],
        'presence': {uid: 1, other: 1},
      };
      final afkHostRoom = {
        'host': uid,
        'players': [uid, other],
        'afkPlayerIds': {uid: true},
        'presence': {other: 1},
      };
      final outsiderRoom = {
        'host': other,
        'players': [other, 'user3'],
        'presence': {other: 1},
      };

      expect(RoomConfig.canUserSpectateRoom(connectedHostRoom, uid), isFalse);
      expect(RoomConfig.canUserSpectateRoom(connectedGuestRoom, uid), isFalse);
      expect(RoomConfig.canUserSpectateRoom(afkHostRoom, uid), isTrue);
      expect(RoomConfig.canUserSpectateRoom(outsiderRoom, uid), isTrue);
    });

    test('isConnectedParticipant は接続中かつ非AFKの参加者のみ true', () {
      const uid = 'user1';
      final data = {
        'players': [uid, 'user2'],
        'presence': {uid: 1},
        'afkPlayerIds': {uid: true},
      };
      expect(RoomConfig.isConnectedParticipant(data, uid), isFalse);
      expect(
        RoomConfig.isConnectedParticipant({
          'players': [uid],
          'presence': {uid: 1},
        }, uid),
        isTrue,
      );
    });
  });
}
