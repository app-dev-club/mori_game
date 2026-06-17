import 'package:shared_preferences/shared_preferences.dart';

/// 対戦画面の表示に関するローカル設定
class GameDisplaySettings {
  static const _hideOpponentNamesKey = 'hide_opponent_names';

  Future<bool> getHideOpponentNames() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideOpponentNamesKey) ?? false;
  }

  Future<void> setHideOpponentNames(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideOpponentNamesKey, value);
  }
}
