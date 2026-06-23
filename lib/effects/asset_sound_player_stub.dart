/// 非対応プラットフォーム用
abstract class AssetSoundHandle {
  Future<void> stop();
  Future<void> dispose();
}

Future<AssetSoundHandle?> playAssetSound(String assetPath) async => null;
