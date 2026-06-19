import '../features/game/game_board_view.dart';

/// 試合記録用のカード・手札シリアライズ
class MatchRecordCodec {
  static Map<String, dynamic> card(CardWidget card) => {
        'number': card.number,
        'suit': card.suit.name,
      };

  static CardWidget parseCard(Map<dynamic, dynamic> json) => CardWidget(
        number: json['number'] as int,
        suit: Suit.values.firstWhere((e) => e.name == json['suit']),
      );

  static List<Map<String, dynamic>> hand(List<CardWidget> hand) =>
      hand.map(card).toList();

  static List<CardWidget> parseHand(List<dynamic> raw) => raw
      .map((e) => parseCard(Map<dynamic, dynamic>.from(e as Map)))
      .toList();

  static Map<String, dynamic> field(int fieldNumber, Suit fieldSuit) => {
        'number': fieldNumber,
        'suit': fieldSuit.name,
      };

  static Map<String, List<Map<String, dynamic>>> handsMap(
    Map<String, List<CardWidget>> allHands,
  ) =>
      allHands.map((pid, cards) => MapEntry(pid, hand(cards)));

  static String buildRecordId({
    required String roomId,
    required int matchIndex,
    required int startedAtMs,
  }) =>
      '${roomId}_m${matchIndex}_$startedAtMs';
}
