import 'adsense_init_stub.dart'
    if (dart.library.js_interop) 'adsense_init_web.dart' as impl;

Future<void> initializeAdSenseForWeb() => impl.initializeAdSenseForWeb();
