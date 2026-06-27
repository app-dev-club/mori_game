import 'package:web/web.dart' as web;

const _moriVolumeKey = 'sound_volume_mori';
const _playVolumeKey = 'sound_volume_play';
const _selectionVolumeKey = 'sound_volume_selection';

double? _memoryMoriVolume;
double? _memoryPlayVolume;
double? _memorySelectionVolume;

double _parseVolume(String? raw, double? memory) {
  if (memory != null) return memory.clamp(0.0, 1.0);
  if (raw == null || raw.isEmpty) return 1.0;
  return (double.tryParse(raw) ?? 1.0).clamp(0.0, 1.0);
}

Future<double> getMoriVolumeStorage() async {
  try {
    return _parseVolume(
      web.window.localStorage.getItem(_moriVolumeKey),
      _memoryMoriVolume,
    );
  } catch (_) {
    return _memoryMoriVolume ?? 1.0;
  }
}

Future<double> getPlayVolumeStorage() async {
  try {
    return _parseVolume(
      web.window.localStorage.getItem(_playVolumeKey),
      _memoryPlayVolume,
    );
  } catch (_) {
    return _memoryPlayVolume ?? 1.0;
  }
}

Future<double> getSelectionVolumeStorage() async {
  try {
    return _parseVolume(
      web.window.localStorage.getItem(_selectionVolumeKey),
      _memorySelectionVolume,
    );
  } catch (_) {
    return _memorySelectionVolume ?? 1.0;
  }
}

Future<void> _storeVolume(String key, double value, void Function(double) setMemory) async {
  final clamped = value.clamp(0.0, 1.0);
  setMemory(clamped);
  try {
    web.window.localStorage.setItem(key, clamped.toString());
  } catch (_) {}
}

Future<void> setMoriVolumeStorage(double value) =>
    _storeVolume(_moriVolumeKey, value, (v) => _memoryMoriVolume = v);

Future<void> setPlayVolumeStorage(double value) =>
    _storeVolume(_playVolumeKey, value, (v) => _memoryPlayVolume = v);

Future<void> setSelectionVolumeStorage(double value) =>
    _storeVolume(_selectionVolumeKey, value, (v) => _memorySelectionVolume = v);
