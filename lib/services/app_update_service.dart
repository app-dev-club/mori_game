import '../models/app_update_check_result.dart';

import 'app_update_service_stub.dart'
    if (dart.library.io) 'app_update_service_io.dart'
    if (dart.library.js_interop) 'app_update_service_web.dart' as impl;

export '../models/app_update_check_result.dart';

Future<AppUpdateCheckResult> checkForAppUpdate() => impl.checkForAppUpdate();

Future<void> applyAppUpdate(AppUpdateAction action, {String? storeUrl}) =>
    impl.applyAppUpdate(action, storeUrl: storeUrl);
