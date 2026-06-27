/// 非対応プラットフォーム用
abstract class AssetSoundHandle {
  Future<void> stop();
  Future<void> dispose();
}

Future<AssetSoundHandle?> playAssetSound(String assetPath, {double volume = 1.0}) async => null;
