import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/logic/room_authority.dart';

void main() {
  group('RoomAuthority', () {
    test('prefers connected host as authority', () {
      final id = RoomAuthority.resolveAuthorityId(
        playerIds: const ['host', 'guest'],
        hostId: 'host',
        presentPlayerIds: const {'host', 'guest'},
        afkPlayerIds: const {},
      );
      expect(id, 'host');
    });

    test('falls back to first connected player when host is afk', () {
      final id = RoomAuthority.resolveAuthorityId(
        playerIds: const ['host', 'guest'],
        hostId: 'host',
        presentPlayerIds: const {'guest'},
        afkPlayerIds: const {'host'},
      );
      expect(id, 'guest');
    });

    test('returns null when everyone is disconnected', () {
      final id = RoomAuthority.resolveAuthorityId(
        playerIds: const ['host', 'guest'],
        hostId: 'host',
        presentPlayerIds: const {},
        afkPlayerIds: const {'host', 'guest'},
      );
      expect(id, isNull);
    });

    test('needsSubstituteRunner when no connected authority', () {
      expect(
        RoomAuthority.needsSubstituteRunner(
          gameStarted: true,
          playerIds: const ['host', 'guest'],
          afkPlayerIds: const {'host'},
          roomAuthorityId: 'guest',
          hasAutomatedPlayers: true,
        ),
        isFalse,
      );
      expect(
        RoomAuthority.needsSubstituteRunner(
          gameStarted: true,
          playerIds: const ['host', 'guest'],
          afkPlayerIds: const {'host', 'guest'},
          roomAuthorityId: null,
          hasAutomatedPlayers: true,
        ),
        isTrue,
      );
      expect(
        RoomAuthority.needsSubstituteRunner(
          gameStarted: false,
          playerIds: const ['host'],
          afkPlayerIds: const {'host'},
          roomAuthorityId: null,
          hasAutomatedPlayers: true,
        ),
        isFalse,
      );
      expect(
        RoomAuthority.needsSubstituteRunner(
          gameStarted: true,
          playerIds: const ['host', 'guest'],
          afkPlayerIds: const {},
          roomAuthorityId: null,
          hasAutomatedPlayers: false,
        ),
        isTrue,
      );
    });
  });
}
