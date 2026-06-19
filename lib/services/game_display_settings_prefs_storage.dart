import 'package:shared_preferences/shared_preferences.dart';

const _hideOpponentNamesKey = 'hide_opponent_names';

bool? _memoryHideOpponentNames;

Future<bool> getHideOpponentNamesStorage() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hideOpponentNamesKey) ?? false;
  } catch (_) {
    return _memoryHideOpponentNames ?? false;
  }
}

Future<void> setHideOpponentNamesStorage(bool value) async {
  _memoryHideOpponentNames = value;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hideOpponentNamesKey, value);
  } catch (_) {}
}
