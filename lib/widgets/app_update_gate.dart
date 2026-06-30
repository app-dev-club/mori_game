import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_update_service.dart';

/// 起動時と定期チェックで古いクライアントを検知し、更新を促す
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate> with WidgetsBindingObserver {
  Timer? _periodicCheckTimer;
  bool _dialogVisible = false;

  static const _checkInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _periodicCheckTimer = Timer.periodic(_checkInterval, (_) => _checkForUpdate());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  @override
  void dispose() {
    _periodicCheckTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_checkForUpdate());
    }
  }

  Future<void> _checkForUpdate() async {
    if (!mounted || _dialogVisible) return;

    final result = await checkForAppUpdate();
    if (!mounted || !result.updateRequired) return;

    _dialogVisible = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AppUpdateDialog(
        result: result,
        onApply: () async {
          await applyAppUpdate(result.action, storeUrl: result.storeUrl);
        },
      ),
    );
    if (mounted) {
      _dialogVisible = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _AppUpdateDialog extends StatelessWidget {
  const _AppUpdateDialog({
    required this.result,
    required this.onApply,
  });

  final AppUpdateCheckResult result;
  final Future<void> Function() onApply;

  @override
  Widget build(BuildContext context) {
    final versionLine = _versionLine();
    final canApply = result.action != AppUpdateAction.none;

    return AlertDialog(
      backgroundColor: const Color(0xFF2E7D32),
      title: const Text(
        'アップデートのお知らせ',
        style: TextStyle(color: Colors.white),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.updateMessage ?? '新しいバージョンが利用可能です。',
            style: const TextStyle(color: Colors.white70),
          ),
          if (versionLine != null) ...[
            const SizedBox(height: 12),
            Text(
              versionLine,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ],
      ),
      actions: [
        if (canApply)
          FilledButton(
            onPressed: () => onApply(),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.black,
            ),
            child: Text(_primaryActionLabel(result.action)),
          ),
      ],
    );
  }

  String? _versionLine() {
    final local = result.localVersionLabel;
    final remote = result.remoteVersionLabel;
    if (local == null && remote == null) return null;
    if (remote == null) return '現在: $local';
    if (local == null) return '最新: $remote';
    return '現在: $local\n最新: $remote';
  }

  String _primaryActionLabel(AppUpdateAction action) {
    switch (action) {
      case AppUpdateAction.reload:
        return '再読み込み';
      case AppUpdateAction.openStore:
        return 'ストアを開く';
      case AppUpdateAction.none:
        return 'OK';
    }
  }
}
