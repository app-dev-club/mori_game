import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// アプリ全体で共有する効果音（ボタン・カード操作）
class AppSoundEffects {
  AppSoundEffects._();

  static final AppSoundEffects instance = AppSoundEffects._();

  static const _soundButton = 'lib/effects/play/button.mp3';
  static const _soundPlayCard = 'lib/effects/play/playcard.mp3';

  void playButton() => _playSound(_soundButton);

  void playCard() => _playSound(_soundPlayCard);
}

/// ボタン押下音を鳴らしてから処理を実行する
void withButtonSound(VoidCallback action) {
  AppSoundEffects.instance.playButton();
  action();
}

Future<void> _playSound(String assetPath) async {
  try {
    final player = AudioPlayer();
    final data = await rootBundle.load(assetPath);
    await player.play(
      BytesSource(
        data.buffer.asUint8List(),
        mimeType: 'audio/mpeg',
      ),
    );
    player.onPlayerComplete.listen((_) async {
      await player.dispose();
    });
  } catch (e) {
    assert(() {
      debugPrint('効果音の再生に失敗: $e');
      return true;
    }());
  }
}
