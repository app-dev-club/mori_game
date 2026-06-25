import 'package:flutter/foundation.dart';
import 'package:google_adsense/google_adsense.dart';
import 'package:google_adsense/h5.dart';

import 'rewarded_ad_config.dart';

bool _initialized = false;

/// モリー獲得ページなど、コンテンツ付き画面でのみ AdSense を初期化する
Future<void> ensureAdSenseInitialized() async {
  if (_initialized) return;

  final publisherId = RewardedAdConfig.adsensePublisherId;
  if (publisherId.isEmpty || publisherId == '0123456789012345') {
    debugPrint(
      'AdSense: RewardedAdConfig.adsensePublisherId を設定してください',
    );
    return;
  }

  await adSense.initialize(
    publisherId,
    adSenseCodeParameters: AdSenseCodeParameters(
      adbreakTest: kDebugMode ? 'on' : null,
    ),
  );

  h5GamesAds.adConfig(
    AdConfigParameters(
      sound: SoundEnabled.on,
      preloadAdBreaks: PreloadAdBreaks.on,
    ),
  );

  _initialized = true;
}
