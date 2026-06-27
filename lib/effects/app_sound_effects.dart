import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/sound_settings.dart';
import 'asset_sound_player.dart';

/// アプリ全体で共有する効果音（ボタン・カード操作）
class AppSoundEffects {
  AppSoundEffects._();

  static final AppSoundEffects instance = AppSoundEffects._();

  static const _soundButton = 'lib/effects/play/button.mp3';
  static const _soundPlayCard = 'lib/effects/play/playcard.mp3';
  static const _soundMoriPreview = 'lib/effects/mori/sound/mori.mp3';

  void playButton() =>
      unawaited(_playSound(_soundButton, SoundVolumeCategory.selection));

  void playCard() =>
      unawaited(_playSound(_soundPlayCard, SoundVolumeCategory.play));

  /// 設定画面の試聴用
  void preview(SoundVolumeCategory category) {
    final assetPath = switch (category) {
      SoundVolumeCategory.selection => _soundButton,
      SoundVolumeCategory.play => _soundPlayCard,
      SoundVolumeCategory.mori => _soundMoriPreview,
    };
    unawaited(_playSound(assetPath, category));
  }
}

/// ボタン押下音を鳴らしてから処理を実行する
void withButtonSound(VoidCallback action) {
  AppSoundEffects.instance.playButton();
  action();
}

Future<void> _playSound(String assetPath, SoundVolumeCategory category) async {
  final volume = SoundSettings.instance.volumeFor(category);
  if (volume <= 0) return;
  final handle = await playAssetSound(assetPath, volume: volume);
  if (handle == null) return;
  unawaited(
    Future<void>.delayed(const Duration(seconds: 3), () async {
      await handle.dispose();
    }),
  );
}
