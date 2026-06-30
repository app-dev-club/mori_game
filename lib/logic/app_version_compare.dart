/// クライアントとサーバー側のビルド番号を比較する
class AppVersionCompare {
  /// サーバー側ビルド番号の方が大きい場合に更新が必要
  static bool isUpdateRequired({
    required int localBuildNumber,
    required int remoteBuildNumber,
  }) {
    return remoteBuildNumber > localBuildNumber;
  }

  static int? parseBuildNumber(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return int.tryParse(raw);
  }
}
