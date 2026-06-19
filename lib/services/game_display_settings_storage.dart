/// 非対応プラットフォーム用（メモリのみ）
bool? _memoryHideOpponentNames;

Future<bool> getHideOpponentNamesStorage() async =>
    _memoryHideOpponentNames ?? false;

Future<void> setHideOpponentNamesStorage(bool value) async {
  _memoryHideOpponentNames = value;
}
