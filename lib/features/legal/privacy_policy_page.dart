import 'package:flutter/material.dart';

/// AdSense / 広告配信に必要なプライバシーポリシー
class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text(
          'プライバシーポリシー',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [
          _Section(
            title: '1. はじめに',
            body:
                '本サービス「もり」オンライン対戦（以下「本サービス」）は、ユーザーの個人情報および利用データの取り扱いについて、以下のとおりプライバシーポリシーを定めます。',
          ),
          _Section(
            title: '2. 収集する情報',
            body:
                '本サービスでは、ゲームプレイのために Firebase Authentication による認証情報、'
                '対戦記録、モリー（架空通貨）の残高、ルーム参加情報などを保存することがあります。',
          ),
          _Section(
            title: '3. 広告について',
            body:
                '本サービスでは、第三者配信の広告サービス（Google AdSense / Google AdMob 等）を利用する場合があります。'
                '広告配信事業者は、ユーザーの興味に応じた広告を表示するため、Cookie や広告識別子を使用することがあります。'
                'ユーザーは、ブラウザの設定や端末の広告設定により、パーソナライズド広告を無効にできる場合があります。\n\n'
                'リワード広告は、モリー獲得などの説明がある専用ページからのみ、ユーザーの操作によって表示されます。'
                '対戦画面やログイン画面など、ゲーム操作のみを目的とした画面では広告を表示しません。',
          ),
          _Section(
            title: '4. 情報の利用目的',
            body:
                '収集した情報は、対戦の提供、ランキング表示、モリーの管理、不正利用の防止、'
                'およびサービス改善のために利用します。',
          ),
          _Section(
            title: '5. 第三者への提供',
            body:
                '法令に基づく場合を除き、本人の同意なく個人情報を第三者に提供することはありません。'
                '広告配信のため、Google 等の広告パートナーに Cookie や端末情報が送信される場合があります。',
          ),
          _Section(
            title: '6. お問い合わせ',
            body:
                '本ポリシーに関するお問い合わせは、本サービスの運営者までご連絡ください。',
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, height: 1.6, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
