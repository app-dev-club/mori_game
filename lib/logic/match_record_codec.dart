import '../features/game/game_board_view.dart';

/// 試合記録用のカード・手札シリアライズ
class MatchRecordCodec {
  static Map<String, dynamic> card(CardWidget card) => {
        'number': card.number,
        'suit': card.suit.name,
      };

  static int readInt(dynamic value, {int fallback = 0}) {
    if (value is int) return value;
    if (value is num) return value.round();
    return fallback;
  }

  static CardWidget parseCard(Map<dynamic, dynamic> json) => CardWidget(
        number: readInt(json['number']),
        suit: Suit.values.firstWhere(
          (e) => e.name == json['suit']?.toString(),
          orElse: () => Suit.joker,
        ),
      );

  static List<CardWidget> parseHand(List<dynamic> raw) {
    final hand = <CardWidget>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        hand.add(parseCard(Map<dynamic, dynamic>.from(item)));
      } catch (_) {
        // 破損カードはスキップ（Web 本番で型不一致が起きやすい）
      }
    }
    return hand;
  }

  static Map<String, dynamic> field(int fieldNumber, Suit fieldSuit) => {
        'number': fieldNumber,
        'suit': fieldSuit.name,
      };

  /// Firebase Web 書き込み用にキーを String に正規化
  static Map<String, dynamic> toFirebaseMap(Map<dynamic, dynamic> source) {
    return source.map((key, value) {
      final k = key.toString();
      if (value is Map) {
        return MapEntry(k, toFirebaseMap(Map<dynamic, dynamic>.from(value)));
      }
      if (value is List) {
        return MapEntry(
          k,
          value.map((item) {
            if (item is Map) {
              return toFirebaseMap(Map<dynamic, dynamic>.from(item));
            }
            return item;
          }).toList(),
        );
      }
      return MapEntry(k, value);
    });
  }

  static Map<String, List<Map<String, dynamic>>> handsMap(
    Map<String, List<CardWidget>> allHands,
  ) =>
      allHands.map((pid, cards) => MapEntry(pid, hand(cards)));

  static List<Map<String, dynamic>> hand(List<CardWidget> hand) =>
      hand.map(card).toList();

  static String buildRecordId({
    required String roomId,
    required int matchIndex,
    int? startedAtMs,
  }) =>
      '${roomId}_m$matchIndex';
}
