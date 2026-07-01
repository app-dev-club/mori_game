import 'package:flutter_test/flutter_test.dart';
import 'package:mori_game/features/game/game_board_view.dart';
import 'package:mori_game/logic/match_record_codec.dart';
import 'package:mori_game/models/match_event.dart';

void main() {
  group('MatchRecordCodec', () {
    test('カードと手札を往復できる', () {
      const card = CardWidget(number: 7, suit: Suit.heart);
      final json = MatchRecordCodec.card(card);
      final parsed = MatchRecordCodec.parseCard(json);
      expect(parsed.number, 7);
      expect(parsed.suit, Suit.heart);

      // Firebase Web では number が double で返ることがある
      final fromDouble = MatchRecordCodec.parseCard({
        'number': 7.0,
        'suit': 'heart',
      });
      expect(fromDouble.number, 7);

      final hand = [
        const CardWidget(number: 3, suit: Suit.spade),
        const CardWidget(number: 4, suit: Suit.diamond),
      ];
      final serialized = MatchRecordCodec.hand(hand);
      expect(MatchRecordCodec.parseHand(serialized).length, 2);
    });

    test('recordId を生成する', () {
      expect(
        MatchRecordCodec.buildRecordId(
          roomId: '12345',
          matchIndex: 2,
          startedAtMs: 1_700_000_000_000,
        ),
        '12345_m2_1700000000000',
      );
    });
  });

  group('MatchEvent', () {
    test('JSON 往復', () {
      const event = MatchEvent(
        seq: 1,
        type: MatchEventType.playCard,
        atMs: 1000,
        actorId: 'host',
        payload: {
          'card': {'number': 7, 'suit': 'heart'},
        },
      );
      final restored = MatchEvent.fromJson(event.toJson());
      expect(restored.seq, 1);
      expect(restored.type, MatchEventType.playCard);
      expect(restored.actorId, 'host');
    });
  });
}
