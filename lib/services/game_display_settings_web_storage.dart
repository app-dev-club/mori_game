import 'package:web/web.dart' as web;

const _hideOpponentNamesKey = 'hide_opponent_names';

bool? _memoryHideOpponentNames;

Future<bool> getHideOpponentNamesStorage() async {
  try {
    return web.window.localStorage.getItem(_hideOpponentNamesKey) == 'true';
  } catch (_) {
    return _memoryHideOpponentNames ?? false;
  }
}

Future<void> setHideOpponentNamesStorage(bool value) async {
  _memoryHideOpponentNames = value;
  try {
    web.window.localStorage.setItem(_hideOpponentNamesKey, value.toString());
  } catch (_) {}
}
