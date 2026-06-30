import '../models/app_update_check_result.dart';

Future<AppUpdateCheckResult> checkForAppUpdate() =>
    throw UnsupportedError('Unsupported platform');

Future<void> applyAppUpdate(AppUpdateAction action, {String? storeUrl}) =>
    throw UnsupportedError('Unsupported platform');
