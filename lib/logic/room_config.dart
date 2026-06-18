/// ルーム人数に関する定数
class RoomConfig {
  static const int minPlayers = 2;
  static const int defaultMaxPlayers = 4;
  static const int absoluteMaxPlayers = 8;

  static const List<int> maxPlayerOptions = [2, 3, 4, 5, 6, 7, 8];

  /// ルーム作成時に選べる対戦回数
  static const List<int> matchCountOptions = [1, 2, 3, 5, 10];

  static const int defaultMatchCount = 1;

  static int resolveMatchCount(dynamic value) {
    if (value is num) {
      final n = value.round();
      if (matchCountOptions.contains(n)) return n;
      if (n >= 1) return n;
    }
    return defaultMatchCount;
  }

  static int resolveNonNegativeInt(dynamic value, {int fallback = 0}) {
    if (value is num) {
      final n = value.round();
      if (n >= 0) return n;
    }
    return fallback;
  }

  /// シリーズ中、次の対戦を始めるまでの秒数
  static const int seriesNextMatchSeconds = 5;

  static int get seriesNextMatchMs => seriesNextMatchSeconds * 1000;

  /// 既存ルームで maxPlayers が未設定のときのフォールバック
  static int resolveMaxPlayers(dynamic value) {
    if (value is int && maxPlayerOptions.contains(value)) return value;
    return absoluteMaxPlayers;
  }

  static bool isRoomFull(int currentCount, int maxPlayers) =>
      currentCount >= maxPlayers;

  static bool hasMinPlayers(int currentCount) => currentCount >= minPlayers;

  /// ホストが再戦を選ぶまでの制限時間（秒）
  static const int hostRematchDecisionSeconds = 60;

  /// ゲストが再戦に参加するか答えるまでの制限時間（秒）
  static const int guestRematchResponseSeconds = 60;

  static int get hostRematchDecisionMs => hostRematchDecisionSeconds * 1000;
  static int get guestRematchResponseMs => guestRematchResponseSeconds * 1000;

  /// 1手の持ち時間（秒）。超過時は自動で合法手またはドロー
  static const int autoPlayTimeoutSeconds = 10;

  static int get autoPlayTimeoutMs => autoPlayTimeoutSeconds * 1000;

  /// Botの操作までの目安（実際の遅延は持ち時間内でランダム）
  static const int botActionTimeoutSeconds = 2;

  static int get botActionTimeoutMs => botActionTimeoutSeconds * 1000;

  /// 初期フェーズで誰も出せないとき、次の山札を自動でめくるまでの秒数
  static const int initialPhaseAutoFlipSeconds = 5;

  static int get initialPhaseAutoFlipMs => initialPhaseAutoFlipSeconds * 1000;

  /// もり・もり返し宣言後、結果確定までの秒数
  static const int moriResolutionSeconds = 5;

  static int get moriResolutionMs => moriResolutionSeconds * 1000;
}
