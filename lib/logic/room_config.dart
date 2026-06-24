/// ルーム人数に関する定数
class RoomConfig {
  static const int minPlayers = 2;
  static const int defaultMaxPlayers = 4;
  static const int absoluteMaxPlayers = 8;

  /// 対戦人数上限に合わせた Bot 上限（[BotLogic.maxBotSlot] と同値）
  static const int maxBotCount = 7;

  static const List<int> maxPlayerOptions = [2, 3, 4, 5, 6, 7, 8];

  /// ルーム作成時に選べる対戦回数
  static const List<int> matchCountOptions = [1, 2, 3, 5, 10];

  static const int defaultMatchCount = 1;

  /// ルーム作成時に選べる1手あたりの持ち時間（秒）
  static const List<int> turnTimeoutOptions = [5, 7, 10, 15];

  static const int defaultTurnTimeoutSeconds = 10;

  static int resolveTurnTimeoutSeconds(dynamic value) {
    if (value is num) {
      final n = value.round();
      if (turnTimeoutOptions.contains(n)) return n;
      if (n >= 3 && n <= 120) return n;
    }
    return defaultTurnTimeoutSeconds;
  }

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

  /// 指定ユーザーがルームを観戦できるか（ホスト・参加プレイヤーは不可）
  static bool canUserSpectateRoom(Map<dynamic, dynamic> data, String userId) {
    final hostId = data['host']?.toString();
    if (hostId != null && hostId == userId) return false;
    final players = data['players'] as List? ?? [];
    for (final player in players) {
      if (player.toString() == userId) return false;
    }
    return true;
  }

  /// モリーレート（ポイント×レートが増減額）。1以上の整数。
  static const int defaultMorrieRate = 1;

  static int resolveMorrieRate(dynamic value) {
    if (value is num) {
      final n = value.round();
      if (n >= 1) return n;
    }
    return defaultMorrieRate;
  }

  static int? parseMorrieRateInput(String text) {
    final n = int.tryParse(text.trim());
    if (n == null || n < 1) return null;
    return n;
  }

  /// 最低入室モリー（0 = 制限なし）。0以上の整数。
  static const int defaultMinMorrieBalance = 0;

  static int resolveMinMorrieBalance(dynamic value) {
    if (value is num) {
      final n = value.round();
      if (n >= 0) return n;
    }
    return defaultMinMorrieBalance;
  }

  static int? parseMinMorrieBalanceInput(String text) {
    final n = int.tryParse(text.trim());
    if (n == null || n < 0) return null;
    return n;
  }

  static bool meetsMinMorrieRequirement(int balance, int minRequired) =>
      minRequired <= 0 || balance >= minRequired;

  /// ホストが再戦を選ぶまでの制限時間（秒）
  static const int hostRematchDecisionSeconds = 60;

  /// ゲストが再戦に参加するか答えるまでの制限時間（秒）
  static const int guestRematchResponseSeconds = 60;

  static int get hostRematchDecisionMs => hostRematchDecisionSeconds * 1000;
  static int get guestRematchResponseMs => guestRematchResponseSeconds * 1000;

  /// 1手の持ち時間（秒）のデフォルト。ルームごとに [turnTimeoutSeconds] で上書きされる
  static const int autoPlayTimeoutSeconds = defaultTurnTimeoutSeconds;

  static int get autoPlayTimeoutMs => autoPlayTimeoutSeconds * 1000;

  /// 初期フェーズで誰も出せないとき、次の山札を自動でめくるまでの秒数
  static const int initialPhaseAutoFlipSeconds = 5;

  static int get initialPhaseAutoFlipMs => initialPhaseAutoFlipSeconds * 1000;

  /// もり・もり返し宣言後、結果確定までの秒数
  static const int moriResolutionSeconds = 5;

  static int get moriResolutionMs => moriResolutionSeconds * 1000;
}
