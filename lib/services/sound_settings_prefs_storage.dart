import 'package:shared_preferences/shared_preferences.dart';

const _moriVolumeKey = 'sound_volume_mori';
const _playVolumeKey = 'sound_volume_play';
const _selectionVolumeKey = 'sound_volume_selection';

double? _memoryMoriVolume;
double? _memoryPlayVolume;
double? _memorySelectionVolume;

double _readVolume(double? stored, double? memory) {
  if (memory != null) return memory.clamp(0.0, 1.0);
  if (stored == null) return 1.0;
  return stored.clamp(0.0, 1.0);
}

Future<double> getMoriVolumeStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return _readVolume(prefs.getDouble(_moriVolumeKey), _memoryMoriVolume);
  } catch (_) {
    return _memoryMoriVolume ?? 1.0;
  }
}

Future<double> getPlayVolumeStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return _readVolume(prefs.getDouble(_playVolumeKey), _memoryPlayVolume);
  } catch (_) {
    return _memoryPlayVolume ?? 1.0;
  }
}

Future<double> getSelectionVolumeStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return _readVolume(prefs.getDouble(_selectionVolumeKey), _memorySelectionVolume);
  } catch (_) {
    return _memorySelectionVolume ?? 1.0;
  }
}

Future<void> setMoriVolumeStorage(double value) async {
  final clamped = value.clamp(0.0, 1.0);
  _memoryMoriVolume = clamped;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_moriVolumeKey, clamped);
  } catch (_) {}
}

Future<void> setPlayVolumeStorage(double value) async {
  final clamped = value.clamp(0.0, 1.0);
  _memoryPlayVolume = clamped;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_playVolumeKey, clamped);
  } catch (_) {}
}

Future<void> setSelectionVolumeStorage(double value) async {
  final clamped = value.clamp(0.0, 1.0);
  _memorySelectionVolume = clamped;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_selectionVolumeKey, clamped);
  } catch (_) {}
}
