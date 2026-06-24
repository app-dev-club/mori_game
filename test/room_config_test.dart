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

    test('resolveMorrieRate はレートを解決する', () {
      expect(RoomConfig.resolveMorrieRate(10), 10);
      expect(RoomConfig.resolveMorrieRate(null), RoomConfig.defaultMorrieRate);
    });

    test('canUserSpectateRoom はホストと参加プレイヤーを観戦不可にする', () {
      const uid = 'user1';
      const other = 'user2';
      final hostRoom = {
        'host': uid,
        'players': [uid, other],
      };
      final guestRoom = {
        'host': other,
        'players': [uid, other],
      };
      final outsiderRoom = {
        'host': other,
        'players': [other, 'user3'],
      };

      expect(RoomConfig.canUserSpectateRoom(hostRoom, uid), isFalse);
      expect(RoomConfig.canUserSpectateRoom(guestRoom, uid), isFalse);
      expect(RoomConfig.canUserSpectateRoom(outsiderRoom, uid), isTrue);
    });
  });
}
