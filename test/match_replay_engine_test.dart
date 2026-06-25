import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/features/game/game_board_view.dart';
import 'package:mori_game/logic/match_record_codec.dart';
import 'package:mori_game/logic/match_replay_engine.dart';
import 'package:mori_game/models/match_event.dart';
import 'package:mori_game/models/match_record.dart';

void main() {
  group('MatchRecordMetaJson', () {
    test('meta を復元できる', () {
      const meta = MatchRecordMeta(
        recordId: 'room_m1_1000',
        roomId: 'room',
        matchIndex: 1,
        seriesTotal: 3,
        turnTimeoutSeconds: 10,
        playerIds: ['p1', 'bot_1'],
        playerNames: {'p1': '太郎', 'bot_1': 'Bot1'},
        botIds: ['bot_1'],
        startedAtMs: 1000,
      );
      final restored = MatchRecordMetaJson.fromJson(meta.toJson());
      expect(restored.recordId, 'room_m1_1000');
      expect(restored.playerNames['p1'], '太郎');
    });
  });

  group('MatchReplayEngine', () {
    test('initial と events からフレーム列を構築する', () {
      const card7h = CardWidget(number: 7, suit: Suit.heart);
      const card3s = CardWidget(number: 3, suit: Suit.spade);

      final meta = MatchRecordMeta(
        recordId: 'test_m1_1',
        roomId: 'test',
        matchIndex: 1,
        seriesTotal: 1,
        turnTimeoutSeconds: 10,
        playerIds: ['p1', 'p2'],
        playerNames: {'p1': 'A', 'p2': 'B'},
        botIds: [],
        startedAtMs: 1,
      );

      final handP1 = MatchRecordCodec.hand([card7h]);
      final handP2 = MatchRecordCodec.hand([card3s]);
      final field = MatchRecordCodec.field(7, Suit.heart);
      final deck = List.generate(10, (i) => MatchRecordCodec.card(const CardWidget(number: 2, suit: Suit.club)));

      final record = MatchRecord(
        meta: meta,
        initial: {
          'hands': {'p1': handP1, 'p2': handP2},
          'deck': deck,
          'field': field,
          'fieldHistory': [field],
          'currentTurnIndex': 0,
          'isInitialPhase': true,
        },
        events: [
          MatchEvent(
            seq: 1,
            type: MatchEventType.matchStart,
            atMs: 1,
            payload: {},
          ),
          MatchEvent(
            seq: 2,
            type: MatchEventType.playCard,
            atMs: 2,
            actorId: 'p1',
            payload: {
              'card': MatchRecordCodec.card(card3s),
              'field': field,
              'hands': {'p1': [], 'p2': handP2},
              'turnIndex': 1,
              'isInitialPhase': false,
            },
          ),
        ],
        result: MatchRecordResult(
          endReason: 'mori',
          winnerId: 'p2',
          loserId: 'p1',
          endedAtMs: 99,
        ),
      );

      final frames = MatchReplayEngine.buildFrames(record);
      expect(frames.length, 2);
      expect(frames[0].description, '試合開始');
      expect(frames[0].hands['p1']!.length, 1);
      expect(frames[1].description, contains('A'));
      expect(frames[1].hands['p1']!.length, 0);
      expect(frames[1].fieldNumber, 3);
      expect(frames[1].fieldSuit, Suit.spade);
      expect(frames[1].turnIndex, 1);
    });

    test('draw では lastPlayerId を変えず直前に場へ出したプレイヤーを保持する', () {
      const card3s = CardWidget(number: 3, suit: Suit.spade);
      const card5h = CardWidget(number: 5, suit: Suit.heart);
      final field = MatchRecordCodec.field(3, Suit.spade);
      final meta = MatchRecordMeta(
        recordId: 'draw-last-player',
        roomId: 'room',
        matchIndex: 1,
        seriesTotal: 1,
        turnTimeoutSeconds: 10,
        playerIds: ['p1', 'p2'],
        playerNames: const {'p1': 'A', 'p2': 'B'},
        botIds: const [],
        startedAtMs: 1,
      );
      final record = MatchRecord(
        meta: meta,
        initial: {
          'hands': {
            'p1': [MatchRecordCodec.card(card3s)],
            'p2': [MatchRecordCodec.card(card5h)],
          },
          'deck': List<dynamic>.filled(10, MatchRecordCodec.card(card5h)),
          'field': field,
          'fieldHistory': [field],
          'currentTurnIndex': 0,
          'lastPlayerId': 'p1',
          'isInitialPhase': false,
        },
        events: [
          MatchEvent(
            seq: 1,
            type: MatchEventType.playCard,
            atMs: 1,
            actorId: 'p1',
            payload: {
              'card': MatchRecordCodec.card(card3s),
              'hands': {'p1': <dynamic>[], 'p2': [MatchRecordCodec.card(card5h)]},
              'turnIndex': 1,
            },
          ),
          MatchEvent(
            seq: 2,
            type: MatchEventType.draw,
            atMs: 2,
            actorId: 'p2',
            payload: {
              'card': MatchRecordCodec.card(card5h),
              'hands': {'p1': <dynamic>[], 'p2': [MatchRecordCodec.card(card5h), MatchRecordCodec.card(card5h)]},
              'turnIndex': 1,
              'isDrawCompetitive': true,
            },
          ),
        ],
        result: null,
      );

      final frames = MatchReplayEngine.buildFrames(record);
      expect(frames.length, 3);
      expect(frames[1].lastPlayerId, 'p1');
      expect(frames[1].hasDrawPrivilege('p2', meta.playerIds), isTrue);
      expect(frames[2].lastPlayerId, 'p1');
      expect(frames[2].lastDrawerId, 'p2');
      expect(frames[2].isDrawCompetitive, isTrue);
      expect(frames[2].hasDrawPrivilege('p2', meta.playerIds), isFalse);
      expect(frames[2].hasDrawPrivilege('p1', meta.playerIds), isTrue);
    });

    test('範囲外の turnIndex は null に正規化する', () {
      final meta = MatchRecordMeta(
        recordId: 'test',
        roomId: 'test',
        matchIndex: 1,
        seriesTotal: 1,
        turnTimeoutSeconds: 10,
        playerIds: ['p1', 'p2'],
        playerNames: const {},
        botIds: const [],
        startedAtMs: 1,
      );

      expect(MatchReplayEngine.normalizeTurnIndex(-1, 2), isNull);
      expect(MatchReplayEngine.normalizeTurnIndex(99, 2), isNull);
      expect(MatchReplayEngine.normalizeTurnIndex(1, 2), 1);

      final record = MatchRecord(
        meta: meta,
        initial: {
          'hands': <String, dynamic>{},
          'deck': <dynamic>[],
          'field': MatchRecordCodec.field(7, Suit.heart),
          'fieldHistory': <dynamic>[],
          'currentTurnIndex': -1,
          'isInitialPhase': true,
        },
        events: const [],
        result: null,
      );

      final frame = MatchReplayEngine.buildFrames(record).single;
      expect(frame.turnIndex, isNull);
      expect(frame.turnPlayerId(meta.playerIds), isNull);
    });
  });
}
