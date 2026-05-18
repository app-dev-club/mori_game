// lib/models/CardModel.dart

enum Suit { spade, heart, diamond, club, joker }

class CardModel {
  final Suit suit;
  final int number; // 1-13 (J=11, Q=12, K=13). ジョーカーは0等

  CardModel({
    required this.suit,
    required this.number,
  });

  // 今後 Firebase で使うための変換メソッドも用意しておきます
  Map<String, dynamic> toJson() {
    return {
      'suit': suit.name,
      'number': number,
    };
  }

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      suit: Suit.values.byName(json['suit']),
      number: json['number'],
    );
  }
}