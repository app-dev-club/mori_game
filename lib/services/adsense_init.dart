import 'adsense_init_stub.dart'
    if (dart.library.js_interop) 'adsense_init_web.dart' as impl;

/// Web ではコンテンツ付き画面を開いたときだけ AdSense を初期化する
Future<void> ensureAdSenseInitialized() => impl.ensureAdSenseInitialized();
