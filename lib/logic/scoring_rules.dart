import '../features/game/game_board_view.dart';

/// 試合終了時のポイント計算
class ScoringRules {
  /// もり／もり返し宣言時の手札枚数に応じた掛け算係数
  /// ジョーカーは枚数に含めない。
  /// ジョーカー+1枚は通常係数1。オープンジョーカー公開済みなら1枚もり扱いで係数3。
  static int handFactor(List<CardWidget> hand, {bool openJoker = false}) {
    if (hand.isEmpty) return 0;

    final hasJoker = hand.any((c) => c.suit == Suit.joker);
    final effectiveCount = hand.where((c) => c.suit != Suit.joker).length;

    // 1枚もり（ジョーカーなし）のみ係数3
    if (effectiveCount == 1 && !hasJoker) return 3;
    // ジョーカー+1枚: 通常1、オープンジョーカー時は1枚もり扱いで3
    if (effectiveCount == 1 && hasJoker) return openJoker ? 3 : 1;
    // ジョーカーのみは係数1
    if (effectiveCount == 0 && hasJoker) return 1;

    if (effectiveCount == 2 || effectiveCount == 3) return 1;
    if (effectiveCount == 4) return 2;
    if (effectiveCount >= 5) return 5;
    return 1;
  }

  /// もり返し1回ごとに×2（0回=×1, 1回=×2, 2回=×4…）
  static int moriGaeshiMultiplier(int moriGaeshiCount) {
    if (moriGaeshiCount <= 0) return 1;
    return 1 << moriGaeshiCount;
  }

  static int burstPenalty() => 2;

  /// 各宣言の係数をすべて掛け合わせ、もり返し倍率を掛けたポイント
  static int moriWinnerDelta(List<int> declarationFactors, int moriGaeshiCount) {
    if (declarationFactors.isEmpty) return 0;
    var product = 1;
    for (final factor in declarationFactors) {
      product *= factor;
    }
    return product * moriGaeshiMultiplier(moriGaeshiCount);
  }

  static String formatSignedPoints(int points) =>
      points >= 0 ? '+$points' : '$points';

  static String formatFactorFormula(List<int> declarationFactors, int moriGaeshiCount) {
    if (declarationFactors.isEmpty) return '0';
    final parts = declarationFactors.map((f) => '$f').toList();
    final gaeshiMult = moriGaeshiMultiplier(moriGaeshiCount);
    if (gaeshiMult > 1) parts.add('$gaeshiMult');
    return parts.join('×');
  }

  /// 今回の試合で加算したポイントの説明文
  static String describeMoriScoring({
    required String winnerName,
    required String loserName,
    required List<int> declarationFactors,
    required int moriGaeshiCount,
    required int delta,
  }) {
    final formula = formatFactorFormula(declarationFactors, moriGaeshiCount);
    return '$winnerName ${formatSignedPoints(delta)}点 / '
        '$loserName ${formatSignedPoints(-delta)}点\n'
        '（$formula = $delta点）';
  }

  static String describeBurstScoring({
    required String burstPlayerName,
  }) {
    return '$burstPlayerName ${formatSignedPoints(-burstPenalty())}点（バースト）';
  }
}
