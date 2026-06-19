import 'game_display_settings_storage.dart'
    if (dart.library.io) 'game_display_settings_prefs_storage.dart'
    if (dart.library.js_interop) 'game_display_settings_web_storage.dart'
    if (dart.library.html) 'game_display_settings_web_storage.dart' as storage;

/// 対戦画面の表示に関するローカル設定
class GameDisplaySettings {
  Future<bool> getHideOpponentNames() => storage.getHideOpponentNamesStorage();

  Future<void> setHideOpponentNames(bool value) =>
      storage.setHideOpponentNamesStorage(value);
}
