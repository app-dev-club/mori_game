import 'package:flutter/material.dart';

import '../../logic/morrie_rules.dart';
import '../../services/rewarded_ad_config.dart';
import '../common/morrie_ad_reward.dart';
import '../legal/privacy_policy_page.dart';
import '../rules/mori_rules_page.dart';

/// モリー獲得の説明とリワード広告（コンテンツ付き画面でのみ広告を表示）
class MorrieRewardPage extends StatefulWidget {
  final VoidCallback? onBalanceUpdated;

  const MorrieRewardPage({super.key, this.onBalanceUpdated});

  @override
  State<MorrieRewardPage> createState() => _MorrieRewardPageState();
}

class _MorrieRewardPageState extends State<MorrieRewardPage> {
  @override
  void initState() {
    super.initState();
    MorrieAdReward.prepareAdEnvironment();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text(
          'モリーをもらう',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          _contentCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'モリーとは',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'モリーは「もり」オンライン対戦で使う架空の通貨です。'
                  '対戦ルームに入室したり、シリーズ戦の賭けに参加するために使います。',
                  style: TextStyle(color: Colors.white70, height: 1.55, fontSize: 15),
                ),
                const SizedBox(height: 12),
                Text(
                  '動画広告を最後まで視聴すると、モリー ${MorrieRules.adRewardAmount} を獲得できます。',
                  style: TextStyle(color: Colors.lightGreenAccent.shade100, height: 1.5, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _contentCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'モリーの使い方',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 10),
                _Bullet('ルーム作成・参加時に、設定された最低入室モリー以上の所持が必要な場合があります。'),
                _Bullet('対戦の結果に応じてモリーが増減します（ルームのレート設定による）。'),
                _Bullet('Bot との対戦では、Bot のモリーは固定値として扱われます。'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _contentCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ゲームについて',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '「もり」はトランプを使ったオンライン対戦ゲームです。'
                  '場札と手札の数字を組み合わせて「もり」「もり返し」を宣言し、最後に宣言したプレイヤーが勝利します。',
                  style: TextStyle(color: Colors.white70, height: 1.55, fontSize: 15),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const MoriRulesPage()),
                    );
                  },
                  icon: const Icon(Icons.menu_book, color: Colors.tealAccent),
                  label: const Text('ルールを読む', style: TextStyle(color: Colors.tealAccent)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          if (RewardedAdConfig.adsEnabled)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => MorrieAdReward.watchAndGrant(
                  context,
                  onBalanceUpdated: widget.onBalanceUpdated,
                ),
                icon: const Icon(Icons.play_circle_outline),
                label: Text('動画を見てモリー ${MorrieRules.adRewardAmount} をもらう'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.lightGreen,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            )
          else
            _contentCard(
              child: const Text(
                'モリー獲得機能は現在準備中です。公開後、このページから動画視聴でモリーを獲得できます。',
                style: TextStyle(color: Colors.white60, height: 1.5, fontSize: 14),
              ),
            ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                );
              },
              child: const Text('プライバシーポリシー', style: TextStyle(color: Colors.white54)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentCard({required Widget child}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('・', style: TextStyle(color: Colors.orangeAccent, fontSize: 15)),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.5, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
