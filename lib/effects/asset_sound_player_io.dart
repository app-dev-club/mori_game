import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'asset_sound_player_stub.dart';

bool _audioContextConfigured = false;

/// pubspec の assets が `lib/effects/...` 直下のため、デフォルトの `assets/` 接頭辞は使わない。
final AudioCache _assetSoundCache = AudioCache(prefix: '');

Future<void> _ensureAudioContext() async {
  if (_audioContextConfigured) return;
  _audioContextConfigured = true;
  await AudioPlayer.global.setAudioContext(
    AudioContext(
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
      ),
      android: const AudioContextAndroid(
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.game,
        audioFocus: AndroidAudioFocus.gain,
      ),
    ),
  );
}

class _IoAssetSoundHandle implements AssetSoundHandle {
  _IoAssetSoundHandle(this._player);

  final AudioPlayer _player;

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}

Future<AssetSoundHandle?> playAssetSound(String assetPath, {double volume = 1.0}) async {
  final clamped = volume.clamp(0.0, 1.0);
  if (clamped <= 0) return null;
  try {
    await _ensureAudioContext();
    final player = AudioPlayer();
    player.audioCache = _assetSoundCache;
    await player.setVolume(clamped);
    await player.play(AssetSource(assetPath));
    return _IoAssetSoundHandle(player);
  } catch (e, stack) {
    debugPrint('効果音の再生に失敗 ($assetPath): $e\n$stack');
    return null;
  }
}
