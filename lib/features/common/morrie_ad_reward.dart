import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../logic/morrie_rules.dart';
import '../../services/morrie_service.dart';
import '../../services/rewarded_ad_config.dart';
import '../../services/rewarded_ad_service.dart';
import 'app_side_bar.dart';

/// 広告視聴報酬（モリー）の付与フロー
class MorrieAdReward {
  MorrieAdReward._();

  static bool _watching = false;
  static final MorrieService _morrieService = MorrieService();

  static AppSideBarItem sideBarItem(
    BuildContext context, {
    VoidCallback? onBalanceUpdated,
  }) {
    return AppSideBarItem(
      label: 'モリーをもらう',
      icon: Icons.redeem,
      accent: Colors.lightGreenAccent,
      enabled: RewardedAdConfig.adsEnabled,
      onTap: RewardedAdConfig.adsEnabled
          ? () => watchAndGrant(
                context,
                onBalanceUpdated: onBalanceUpdated,
              )
          : null,
    );
  }

  static Future<void> watchAndGrant(
    BuildContext context, {
    VoidCallback? onBalanceUpdated,
  }) async {
    if (!RewardedAdConfig.adsEnabled) return;
    if (_watching) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showMessage(context, 'ログインが必要です');
      return;
    }

    _watching = true;
    var loadingOpen = false;
    try {
      if (context.mounted) {
        loadingOpen = true;
        unawaited(
          showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 20),
                  const Text('準備中…'),
                  const SizedBox(height: 8),
                  Text(
                    'モリー ${MorrieRules.adRewardAmount} を獲得できます',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        );
      }

      final result = await showRewardedAd();
      if (context.mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingOpen = false;
      }
      if (!context.mounted) return;

      if (!result.completed) {
        _showMessage(
          context,
          result.errorMessage ?? '広告を最後まで視聴してください',
        );
        return;
      }

      final balance = await _morrieService.grantAdReward(uid);
      if (!context.mounted) return;

      _showMessage(
        context,
        'モリー ${MorrieRules.adRewardAmount} を獲得しました（所持: $balance）',
      );
      onBalanceUpdated?.call();
    } finally {
      if (context.mounted && loadingOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _watching = false;
    }
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
