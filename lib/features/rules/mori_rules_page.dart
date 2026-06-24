import 'package:flutter/material.dart';

/// 公式ルールブック（docs/mori_game_rule.md）に基づくルール説明ページ
class MoriRulesPage extends StatelessWidget {
  const MoriRulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text(
          'もり ルール',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: const [
          _IntroCard(),
          SizedBox(height: 20),
          _Section(
            number: '1',
            title: 'ゲームの目的',
            children: [
              _Bullet('最後に「もり」または「もり返し」を宣言したプレイヤーが勝利します。'),
              _Bullet('最後に「もり」または「もり返し」を宣言されたプレイヤーが敗北します。'),
            ],
          ),
          _Section(
            number: '2',
            title: '基本的な進行',
            children: [
              _Subheading('ゲームの開始'),
              _Bullet('山札から最初のカード（場札）を1枚めくります。ホストがめくった時点で、新規の入室はできません。'),
              _Bullet('最初の1枚目は、全員が早い者勝ちで同じ数字のカードを出せます。'),
              _Bullet('誰も出せない場合、ホストは山札からもう1枚めくります。'),
              _Bullet('誰かがカードを出すと、隣の人にターンが移りゲームが始まります。'),
              _Bullet('場にジョーカーが出た場合は、早い者勝ちでどんなカードも出せます。'),
              SizedBox(height: 12),
              _Subheading('ターン制と割り込み'),
              _Bullet('基本はターン制で進行します。'),
              _Bullet('自分のターン: 場と同じスートまたは同じ数字のカードを1枚出せます。'),
              _Bullet('自分のターン以外: 場と同じ数字のカードを持っているときだけ、早い者勝ちで割り込んで出せます。'),
            ],
          ),
          _Section(
            number: '3',
            title: '「もり」',
            children: [
              _Bullet('相手が出したカードに対し、条件を満たせば「もり」を宣言できます。'),
              _Bullet('宣言が成功した時点でゲーム終了・勝敗確定です。'),
              _Bullet('自分が出したカードに「もり」を宣言すると自滅になります。'),
              _Bullet('権利がある間は、ゲーム終了までいつでも宣言できます。'),
              SizedBox(height: 12),
              _Subheading('成立条件（場の数字を X とする）'),
              _Bullet('手札1枚: そのカードの数字が X と一致'),
              _Bullet('手札2枚: 2枚を四則演算（＋−×÷）した結果が X と一致（例: 場7に手札3・4 → 3+4=7）'),
              _Bullet('手札3枚以上: 手札すべての合計が X と一致'),
              _Bullet('ジョーカーは手札の枚数にカウントしません（3枚＋ジョーカーなら2枚扱いで四則演算もり可）'),
              _Bullet('J・Q・K はそれぞれ 11・12・13 として扱います。'),
            ],
          ),
          _Section(
            number: '4',
            title: '「もり返し」',
            children: [
              _Bullet('誰かが「もり」を宣言した直後、他プレイヤーも条件を満たせば宣言できます。'),
              _Bullet('最後に「もり返し」を宣言した人が勝利者になります。'),
              _Bullet('直前に「もり」または「もり返し」を宣言していた人が敗北者になります。'),
              _Bullet('もり返しフェーズでは、自分が出した場札に対しても宣言できます。'),
              _Bullet('もり返しは、他プレイヤーの宣言から5秒間のみ可能です。'),
            ],
          ),
          _Section(
            number: '5',
            title: 'ドローとバースト',
            children: [
              _Bullet('自分のターンに、山札からカードを1枚だけドローできます。'),
              _Bullet('ドロー後、条件を満たす手札のカードを出せます（引いたカード以外でも可）。'),
              _Bullet('ドローした瞬間、次のプレイヤーも出す・引く権利が発生し、早い者勝ちで進行します。'),
              _Bullet('7枚目を引いて出せるカードがないときはバーストとなり、その人だけが負けです。'),
              _Bullet('7枚目のドロー時は、次の人にターンは移りません。'),
            ],
          ),
        ],
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orangeAccent.withValues(alpha: 0.6)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'もり 公式ルール',
            style: TextStyle(
              color: Colors.orangeAccent,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'オンライン対戦の基本ルールです。ルームごとに対戦回数・持ち時間・モリーレートなどが設定される場合があります。',
            style: TextStyle(color: Colors.white70, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.number,
    required this.title,
    required this.children,
  });

  final String number;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.orangeAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent),
                ),
                child: Text(
                  number,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _Subheading extends StatelessWidget {
  const _Subheading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Colors.orangeAccent, fontSize: 16)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
