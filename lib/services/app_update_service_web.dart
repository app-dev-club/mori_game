import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:web/web.dart' as web;

import '../logic/app_version_compare.dart';
import '../models/app_update_check_result.dart';

Future<AppUpdateCheckResult> checkForAppUpdate() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final localBuild = AppVersionCompare.parseBuildNumber(packageInfo.buildNumber);
    if (localBuild == null) return AppUpdateCheckResult.none;

    final cacheBust = DateTime.now().millisecondsSinceEpoch;
    final uri = Uri.base.resolve('version.json?_=$cacheBust');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return AppUpdateCheckResult.none;

    final json = jsonDecode(response.body);
    if (json is! Map) return AppUpdateCheckResult.none;

    final remoteBuild = AppVersionCompare.parseBuildNumber(
      json['build_number']?.toString(),
    );
    if (remoteBuild == null) return AppUpdateCheckResult.none;

    final remoteVersion = json['version']?.toString();
    final updateRequired = AppVersionCompare.isUpdateRequired(
      localBuildNumber: localBuild,
      remoteBuildNumber: remoteBuild,
    );
    if (!updateRequired) return AppUpdateCheckResult.none;

    return AppUpdateCheckResult(
      updateRequired: true,
      localVersionLabel: '${packageInfo.version}+$localBuild',
      remoteVersionLabel: remoteVersion != null ? '$remoteVersion+$remoteBuild' : null,
      updateMessage: '新しいバージョンが公開されました。続けるにはページを再読み込みしてください。',
      action: AppUpdateAction.reload,
    );
  } catch (_) {
    return AppUpdateCheckResult.none;
  }
}

Future<void> applyAppUpdate(AppUpdateAction action, {String? storeUrl}) async {
  if (action != AppUpdateAction.reload) return;
  web.window.location.reload();
}
