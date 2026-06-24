import 'package:flutter/foundation.dart';
import 'package:google_adsense/google_adsense.dart';
import 'package:google_adsense/h5.dart';

import 'rewarded_ad_config.dart';

Future<void> initializeAdSenseForWeb() async {
  final publisherId = RewardedAdConfig.adsensePublisherId;
  if (publisherId.isEmpty || publisherId == '0123456789012345') {
    debugPrint(
      'AdSense: RewardedAdConfig.adsensePublisherId を設定してください',
    );
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
}
