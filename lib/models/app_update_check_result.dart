enum AppUpdateAction { reload, openStore, none }

class AppUpdateCheckResult {
  const AppUpdateCheckResult({
    required this.updateRequired,
    this.localVersionLabel,
    this.remoteVersionLabel,
    this.updateMessage,
    this.action = AppUpdateAction.none,
    this.storeUrl,
  });

  final bool updateRequired;
  final String? localVersionLabel;
  final String? remoteVersionLabel;
  final String? updateMessage;
  final AppUpdateAction action;
  final String? storeUrl;

  static const none = AppUpdateCheckResult(updateRequired: false);
}
