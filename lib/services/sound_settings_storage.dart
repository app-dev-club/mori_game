/// 非対応プラットフォーム用（メモリのみ）
double? _memoryMoriVolume;
double? _memoryPlayVolume;
double? _memorySelectionVolume;

Future<double> getMoriVolumeStorage() async => _memoryMoriVolume ?? 1.0;

Future<double> getPlayVolumeStorage() async => _memoryPlayVolume ?? 1.0;

Future<double> getSelectionVolumeStorage() async => _memorySelectionVolume ?? 1.0;

Future<void> setMoriVolumeStorage(double value) async {
  _memoryMoriVolume = value;
}

Future<void> setPlayVolumeStorage(double value) async {
  _memoryPlayVolume = value;
}

Future<void> setSelectionVolumeStorage(double value) async {
  _memorySelectionVolume = value;
}
