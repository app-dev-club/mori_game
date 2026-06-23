import 'dart:async';

import 'package:flutter/foundation.dart';

import 'asset_sound_player.dart';

/// アプリ全体で共有する効果音（ボタン・カード操作）
class AppSoundEffects {
  AppSoundEffects._();

  static final AppSoundEffects instance = AppSoundEffects._();

  static const _soundButton = 'lib/effects/play/button.mp3';
  static const _soundPlayCard = 'lib/effects/play/playcard.mp3';

  void playButton() => unawaited(_playSound(_soundButton));

  void playCard() => unawaited(_playSound(_soundPlayCard));
}

/// ボタン押下音を鳴らしてから処理を実行する
void withButtonSound(VoidCallback action) {
  AppSoundEffects.instance.playButton();
  action();
}

Future<void> _playSound(String assetPath) async {
  final handle = await playAssetSound(assetPath);
  if (handle == null) return;
  // 短い効果音は再生開始後にハンドルを解放（Web は要素が再生完了まで保持）
  unawaited(
    Future<void>.delayed(const Duration(seconds: 3), () async {
      await handle.dispose();
    }),
  );
}
