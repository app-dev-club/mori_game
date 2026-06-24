import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'rewarded_ad_config.dart';
import 'rewarded_ad_service_stub.dart';

RewardedAd? _rewardedAd;
bool _loading = false;
bool _loadFailed = false;

bool get _isSupportedMobile =>
    !kIsWeb && (Platform.isAndroid || Platform.isIOS);

Future<void> initializeRewardedAds() async {
  if (!_isSupportedMobile) return;
  await MobileAds.instance.initialize();
  _loadRewardedAd();
}

void _loadRewardedAd() {
  if (!_isSupportedMobile || _loading || _rewardedAd != null) return;

  final adUnitId = RewardedAdConfig.mobileRewardedAdUnitId;
  if (adUnitId.isEmpty) return;

  _loading = true;
  _loadFailed = false;
  RewardedAd.load(
    adUnitId: adUnitId,
    request: const AdRequest(),
    rewardedAdLoadCallback: RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        _rewardedAd = ad;
        _loading = false;
      },
      onAdFailedToLoad: (error) {
        _rewardedAd = null;
        _loading = false;
        _loadFailed = true;
        debugPrint('Rewarded ad load failed: ${error.message}');
      },
    ),
  );
}

Future<RewardedAd?> _waitForLoaded({
  Duration timeout = const Duration(seconds: 12),
}) async {
  if (_rewardedAd != null) return _rewardedAd;
  if (!_loading) _loadRewardedAd();

  final deadline = DateTime.now().add(timeout);
  while (_rewardedAd == null && DateTime.now().isBefore(deadline)) {
    if (_loadFailed) return null;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return _rewardedAd;
}

Future<RewardedAdResult> showRewardedAd() async {
  if (!_isSupportedMobile) {
    return const RewardedAdResult(
      completed: false,
      errorMessage: 'この端末では広告を表示できません',
    );
  }

  final ad = await _waitForLoaded();
  if (ad == null) {
    _loadFailed = false;
    _loadRewardedAd();
    return const RewardedAdResult(
      completed: false,
      errorMessage: '広告の読み込みに失敗しました。しばらくしてからお試しください',
    );
  }

  final completer = Completer<bool>();
  var rewardEarned = false;

  ad.fullScreenContentCallback = FullScreenContentCallback(
    onAdDismissedFullScreenContent: (dismissedAd) {
      dismissedAd.dispose();
      _rewardedAd = null;
      _loadRewardedAd();
      if (!completer.isCompleted) completer.complete(rewardEarned);
    },
    onAdFailedToShowFullScreenContent: (failedAd, error) {
      failedAd.dispose();
      _rewardedAd = null;
      _loadRewardedAd();
      debugPrint('Rewarded ad show failed: ${error.message}');
      if (!completer.isCompleted) completer.complete(false);
    },
  );

  ad.show(
    onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
      rewardEarned = true;
    },
  );

  final completed = await completer.future;
  if (completed) {
    return const RewardedAdResult(completed: true);
  }
  return const RewardedAdResult(
    completed: false,
    errorMessage: '広告を最後まで視聴してください',
  );
}
