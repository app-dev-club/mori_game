import 'sound_settings_storage.dart'
    if (dart.library.io) 'sound_settings_prefs_storage.dart'
    if (dart.library.js_interop) 'sound_settings_web_storage.dart'
    if (dart.library.html) 'sound_settings_web_storage.dart' as storage;

/// 効果音の種類（設定ページの音量と対応）
enum SoundVolumeCategory {
  mori,
  play,
  selection,
}

/// 効果音の音量設定（5段階）
class SoundSettings {
  SoundSettings._();

  static final SoundSettings instance = SoundSettings._();

  static const int volumeLevelCount = 5;
  static const int defaultLevel = 5;

  /// 段階 1〜5 に対応する再生音量（1 = オフ）
  static const List<double> levelToVolume = [0.0, 0.25, 0.5, 0.75, 1.0];

  int _moriLevel = defaultLevel;
  int _playLevel = defaultLevel;
  int _selectionLevel = defaultLevel;

  int get moriLevel => _moriLevel;
  int get playLevel => _playLevel;
  int get selectionLevel => _selectionLevel;

  double get moriVolume => volumeForLevel(_moriLevel);
  double get playVolume => volumeForLevel(_playLevel);
  double get selectionVolume => volumeForLevel(_selectionLevel);

  static double volumeForLevel(int level) {
    final index = (level - 1).clamp(0, volumeLevelCount - 1);
    return levelToVolume[index];
  }

  static int levelFromVolume(double volume) {
    var bestLevel = defaultLevel;
    var bestDiff = double.infinity;
    for (var i = 0; i < volumeLevelCount; i++) {
      final diff = (volume - levelToVolume[i]).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        bestLevel = i + 1;
      }
    }
    return bestLevel;
  }

  static String levelLabel(int level) => switch (level) {
        1 => 'オフ',
        2 => '小',
        3 => '中',
        4 => '大',
        _ => '最大',
      };

  int levelFor(SoundVolumeCategory category) => switch (category) {
        SoundVolumeCategory.mori => _moriLevel,
        SoundVolumeCategory.play => _playLevel,
        SoundVolumeCategory.selection => _selectionLevel,
      };

  double volumeFor(SoundVolumeCategory category) =>
      volumeForLevel(levelFor(category));

  Future<void> load() async {
    final results = await Future.wait([
      storage.getMoriVolumeStorage(),
      storage.getPlayVolumeStorage(),
      storage.getSelectionVolumeStorage(),
    ]);
    _moriLevel = levelFromVolume(results[0]);
    _playLevel = levelFromVolume(results[1]);
    _selectionLevel = levelFromVolume(results[2]);
  }

  Future<void> setLevel(SoundVolumeCategory category, int level) async {
    final clamped = level.clamp(1, volumeLevelCount);
    final volume = volumeForLevel(clamped);
    switch (category) {
      case SoundVolumeCategory.mori:
        _moriLevel = clamped;
        await storage.setMoriVolumeStorage(volume);
      case SoundVolumeCategory.play:
        _playLevel = clamped;
        await storage.setPlayVolumeStorage(volume);
      case SoundVolumeCategory.selection:
        _selectionLevel = clamped;
        await storage.setSelectionVolumeStorage(volume);
    }
  }
}
