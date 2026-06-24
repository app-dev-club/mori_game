import 'package:flutter/foundation.dart';

/// 広告 ID の設定。
///
/// Web: [adsensePublisherId]（AdSense H5 Games Ads）
/// Android / iOS: AdMob（`google_mobile_ads`）
class RewardedAdConfig {
  RewardedAdConfig._();

  /// 広告視聴機能を有効にするか（AdSense 承認前は false）
  static const bool adsEnabled = false;

  /// AdSense パブリッシャー ID（数字のみ、`pub-` や `ca-pub-` は付けない）
  ///
  /// 取得: AdSense → アカウント → アカウント情報 → パブリッシャー ID
  /// 例: `pub-1234567890123456` なら `1234567890123456`
  ///
  /// H5 Games Ads のベータ申請が必要:
  /// https://adsense.google.com/start/h5-beta/
  static const String adsensePublisherId = '5863667813029977';

  /// H5 リワード広告の内部名（プレイヤーには表示されない）
  static const String adsenseRewardedPlacementName = 'morrie-reward';

  /// Android AdMob アプリ ID（テスト用）
  static const String androidAppId =
      'ca-app-pub-3940256099942544~3347511713';

  /// iOS AdMob アプリ ID（テスト用）
  static const String iosAppId = 'ca-app-pub-3940256099942544~1458002511';

  /// リワード広告ユニット ID（プラットフォーム別テスト用）
  static String get mobileRewardedAdUnitId {
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'ca-app-pub-3940256099942544/5224354917';
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return 'ca-app-pub-3940256099942544/1712485313';
    }
    return '';
  }
}
