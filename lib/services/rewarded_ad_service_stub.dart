class RewardedAdResult {
  const RewardedAdResult({
    required this.completed,
    this.errorMessage,
  });

  final bool completed;
  final String? errorMessage;
}

Future<void> initializeRewardedAds() async {}

Future<RewardedAdResult> showRewardedAd() async {
  return const RewardedAdResult(
    completed: false,
    errorMessage: 'この端末では広告を表示できません',
  );
}
