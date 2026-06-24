import 'rewarded_ad_service_stub.dart' show RewardedAdResult;

import 'rewarded_ad_service_stub.dart'
    if (dart.library.io) 'rewarded_ad_service_io.dart'
    if (dart.library.js_interop) 'rewarded_ad_service_web.dart' as impl;

export 'rewarded_ad_service_stub.dart' show RewardedAdResult;

Future<void> initializeRewardedAds() => impl.initializeRewardedAds();

Future<RewardedAdResult> showRewardedAd() => impl.showRewardedAd();
