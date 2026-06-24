import 'dart:async';

import 'package:google_adsense/h5.dart';

import 'rewarded_ad_config.dart';
import 'rewarded_ad_service_stub.dart';

Future<void> initializeRewardedAds() async {}

Future<RewardedAdResult> showRewardedAd() async {
  final completer = Completer<RewardedAdResult>();
  var settled = false;

  void settle(RewardedAdResult result) {
    if (settled) return;
    settled = true;
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }

  h5GamesAds.adBreak(
    AdBreakPlacement.rewarded(
      name: RewardedAdConfig.adsenseRewardedPlacementName,
      beforeReward: (showAdFn) {
        // サイドバーで視聴を選んだので、すぐ広告を表示する
        showAdFn();
      },
      adViewed: () {
        settle(const RewardedAdResult(completed: true));
      },
      adDismissed: () {
        settle(
          const RewardedAdResult(
            completed: false,
            errorMessage: '広告を最後まで視聴してください',
          ),
        );
      },
      adBreakDone: (info) {
        if (settled) return;
        settle(
          RewardedAdResult(
            completed: false,
            errorMessage: _messageForBreakStatus(info.breakStatus),
          ),
        );
      },
    ),
  );

  return completer.future;
}

String _messageForBreakStatus(BreakStatus? status) {
  return switch (status) {
    BreakStatus.notReady => '広告の準備ができていません。しばらくしてからお試しください',
    BreakStatus.noAdPreloaded => '広告を読み込み中です。しばらくしてからお試しください',
    BreakStatus.frequencyCapped => '広告の表示間隔が短すぎます。少し待ってからお試しください',
    BreakStatus.dismissed => '広告を最後まで視聴してください',
    BreakStatus.timeout => '広告の読み込みがタイムアウトしました',
    BreakStatus.error => '広告の表示中にエラーが発生しました',
    null => '広告を表示できませんでした',
    _ => '広告の配信がありません。しばらくしてからお試しください',
  };
}
