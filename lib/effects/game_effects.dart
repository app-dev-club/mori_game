import 'dart:async';

import 'package:flutter/foundation.dart';

import '../features/game/game_board_view.dart';
import 'app_sound_effects.dart';
import 'asset_sound_player.dart';

enum MoriVisualEffect {
  mori,
  morigaeshi,
  tankimori,
}

/// 対戦中のもり画像表示と専用効果音
class GameEffects extends ChangeNotifier {
  static const _soundMori = 'lib/effects/mori/sound/mori.mp3';
  static const _soundMorigaeshi = 'lib/effects/mori/sound/morigaeshi.mp3';
  static const _soundTankimori = 'lib/effects/mori/sound/tankimori.mp3';

  static const _imageMori = 'lib/effects/mori/pic/mori.jpg';
  static const _imageMorigaeshi = 'lib/effects/mori/pic/morigaeshi.jpg';
  static const _imageTankimori = 'lib/effects/mori/pic/tankimori.jpg';

  /// もり画像の表示時間
  static const Duration moriVisualDuration = Duration(milliseconds: 2600);

  MoriVisualEffect? _activeVisual;
  int _visualToken = 0;
  AssetSoundHandle? _moriSoundHandle;

  MoriVisualEffect? get activeVisual => _activeVisual;
  int get visualToken => _visualToken;

  static String imageAssetFor(MoriVisualEffect type) => switch (type) {
        MoriVisualEffect.mori => _imageMori,
        MoriVisualEffect.morigaeshi => _imageMorigaeshi,
        MoriVisualEffect.tankimori => _imageTankimori,
      };

  static bool isTankimoriHand(
    List<CardWidget> hand, {
    bool openJoker = false,
  }) {
    final nonJokerCount = hand.where((c) => c.suit != Suit.joker).length;
    if (nonJokerCount != 1) return false;
    // ジョーカー+1枚はオープンジョーカー時のみ単騎もり扱い
    if (hand.any((c) => c.suit == Suit.joker)) return openJoker;
    return true;
  }

  void playButton() => AppSoundEffects.instance.playButton();

  void playCard() => AppSoundEffects.instance.playCard();

  void playMoriDeclaration({
    required List<CardWidget> hand,
    bool openJoker = false,
  }) {
    final type = isTankimoriHand(hand, openJoker: openJoker)
        ? MoriVisualEffect.tankimori
        : MoriVisualEffect.mori;
    _showVisual(type);
  }

  void playMorigaeshi() {
    _showVisual(MoriVisualEffect.morigaeshi);
  }

  void _showVisual(MoriVisualEffect type) {
    _activeVisual = type;
    final token = ++_visualToken;
    notifyListeners();
    unawaited(_playSound(switch (type) {
      MoriVisualEffect.mori => _soundMori,
      MoriVisualEffect.morigaeshi => _soundMorigaeshi,
      MoriVisualEffect.tankimori => _soundTankimori,
    }));
    Future.delayed(moriVisualDuration, () {
      if (_visualToken == token) {
        _activeVisual = null;
        notifyListeners();
      }
    });
  }

  Future<void> _stopMoriSound() async {
    final handle = _moriSoundHandle;
    _moriSoundHandle = null;
    if (handle == null) return;
    try {
      await handle.stop();
      await handle.dispose();
    } catch (_) {}
  }

  Future<void> _playSound(String assetPath) async {
    try {
      await _stopMoriSound();
      _moriSoundHandle = await playAssetSound(assetPath);
    } catch (e) {
      assert(() {
        debugPrint('効果音の再生に失敗: $e');
        return true;
      }());
    }
  }

  @override
  void dispose() {
    _activeVisual = null;
    unawaited(_stopMoriSound());
    super.dispose();
  }
}
