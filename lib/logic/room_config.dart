/// ルーム人数に関する定数
class RoomConfig {
  static const int minPlayers = 2;
  static const int defaultMaxPlayers = 4;
  static const int absoluteMaxPlayers = 8;

  static const List<int> maxPlayerOptions = [2, 3, 4, 5, 6, 7, 8];

  /// 既存ルームで maxPlayers が未設定のときのフォールバック
  static int resolveMaxPlayers(dynamic value) {
    if (value is int && maxPlayerOptions.contains(value)) return value;
    return absoluteMaxPlayers;
  }

  static bool isRoomFull(int currentCount, int maxPlayers) =>
      currentCount >= maxPlayers;
}
