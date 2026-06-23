import 'package:audioplayers/audioplayers.dart';

import 'asset_sound_player_stub.dart';

class _IoAssetSoundHandle implements AssetSoundHandle {
  _IoAssetSoundHandle(this._player);

  final AudioPlayer _player;

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

Future<AssetSoundHandle?> playAssetSound(String assetPath) async {
  final player = AudioPlayer();
  await player.play(AssetSource(assetPath));
  return _IoAssetSoundHandle(player);
}
