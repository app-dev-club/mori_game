import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'asset_sound_player_stub.dart';

class _WebAssetSoundHandle implements AssetSoundHandle {
  _WebAssetSoundHandle(this._audio);

  final web.HTMLAudioElement _audio;

  @override
  Future<void> stop() async {
    _audio.pause();
    _audio.currentTime = 0;
  }

  @override
  Future<void> dispose() async {
    await stop();
    _audio.src = '';
    _audio.removeAttribute('src');
  }
}

String _assetUrl(String assetPath) {
  final base = web.document.querySelector('base')?.getAttribute('href') ?? '/';
  return '${base}assets/$assetPath';
}

Future<AssetSoundHandle?> playAssetSound(String assetPath, {double volume = 1.0}) async {
  final clamped = volume.clamp(0.0, 1.0);
  if (clamped <= 0) return null;
  final audio = web.HTMLAudioElement();
  audio.volume = clamped;
  audio.src = _assetUrl(assetPath);
  try {
    await audio.play().toDart;
  } catch (e) {
    assert(() {
      debugPrint('効果音の再生に失敗: $e');
      return true;
    }());
    return null;
  }
  return _WebAssetSoundHandle(audio);
}
