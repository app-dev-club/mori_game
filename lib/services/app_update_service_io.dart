import 'dart:io' show Platform;

import 'package:firebase_database/firebase_database.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logic/app_version_compare.dart';
import '../models/app_update_check_result.dart';

Future<AppUpdateCheckResult> checkForAppUpdate() async {
  try {
    final packageInfo = await PackageInfo.fromPlatform();
    final localBuild = AppVersionCompare.parseBuildNumber(packageInfo.buildNumber);
    if (localBuild == null) return AppUpdateCheckResult.none;

    final snapshot = await FirebaseDatabase.instance.ref('appMeta').get();
    if (!snapshot.exists || snapshot.value is! Map) {
      return AppUpdateCheckResult.none;
    }

    final meta = Map<Object?, Object?>.from(snapshot.value as Map);
    final remoteBuild = AppVersionCompare.parseBuildNumber(
      meta['minBuildNumber']?.toString(),
    );
    if (remoteBuild == null) return AppUpdateCheckResult.none;

    final updateRequired = AppVersionCompare.isUpdateRequired(
      localBuildNumber: localBuild,
      remoteBuildNumber: remoteBuild,
    );
    if (!updateRequired) return AppUpdateCheckResult.none;

    final remoteVersion = meta['minVersion']?.toString();
    final updateMessage = meta['updateMessage']?.toString();
    final storeUrl = _resolveStoreUrl(meta);

    return AppUpdateCheckResult(
      updateRequired: true,
      localVersionLabel: '${packageInfo.version}+$localBuild',
      remoteVersionLabel: remoteVersion != null ? '$remoteVersion+$remoteBuild' : null,
      updateMessage: updateMessage ??
          '新しいバージョンが公開されました。ストアからアップデートしてください。',
      action: storeUrl != null ? AppUpdateAction.openStore : AppUpdateAction.none,
      storeUrl: storeUrl,
    );
  } catch (_) {
    return AppUpdateCheckResult.none;
  }
}

String? _resolveStoreUrl(Map<Object?, Object?> meta) {
  if (Platform.isAndroid) {
    return meta['androidStoreUrl']?.toString();
  }
  if (Platform.isIOS) {
    return meta['iosStoreUrl']?.toString();
  }
  return meta['storeUrl']?.toString();
}

Future<void> applyAppUpdate(AppUpdateAction action, {String? storeUrl}) async {
  if (action != AppUpdateAction.openStore || storeUrl == null || storeUrl.isEmpty) {
    return;
  }
  final uri = Uri.tryParse(storeUrl);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}
