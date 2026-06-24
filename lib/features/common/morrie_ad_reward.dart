import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../logic/morrie_rules.dart';
import '../../services/morrie_service.dart';
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
      label: '広告視聴',
      icon: Icons.play_circle_outline,
      accent: Colors.lightGreenAccent,
      onTap: () => watchAndGrant(
        context,
        onBalanceUpdated: onBalanceUpdated,
      ),
    );
  }

  static Future<void> watchAndGrant(
    BuildContext context, {
    VoidCallback? onBalanceUpdated,
  }) async {
    if (_watching) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _showMessage(context, 'ログインが必要です');
      return;
    }

    _watching = true;
    try {
      final completed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => const _AdWatchingDialog(),
      );
      if (completed != true || !context.mounted) return;

      final balance = await _morrieService.grantAdReward(uid);
      if (!context.mounted) return;

      _showMessage(
        context,
        'モリー ${MorrieRules.adRewardAmount} を獲得しました（所持: $balance）',
      );
      onBalanceUpdated?.call();
    } finally {
      _watching = false;
    }
  }

  static void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _AdWatchingDialog extends StatefulWidget {
  const _AdWatchingDialog();

  @override
  State<_AdWatchingDialog> createState() => _AdWatchingDialogState();
}

class _AdWatchingDialogState extends State<_AdWatchingDialog> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('広告視聴'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          const Text('広告視聴中…'),
          const SizedBox(height: 8),
          Text(
            '完了後 ${MorrieRules.adRewardAmount} モリーを獲得します',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
