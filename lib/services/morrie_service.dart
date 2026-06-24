import 'package:firebase_database/firebase_database.dart';

import '../logic/bot_logic.dart';
import '../logic/morrie_rules.dart';
import '../logic/rating_logic.dart';

class MorrieSettlementResult {
  final String summary;
  final Map<String, int> deltas;
  final Map<String, int> balances;

  const MorrieSettlementResult({
    required this.summary,
    required this.deltas,
    required this.balances,
  });
}

/// ユーザーアカウントに紐づくモリー残高の読み書きと試合精算
class MorrieService {
  final DatabaseReference _usersRef = FirebaseDatabase.instance.ref('users');

  Future<int> getBalance(String userId) async {
    try {
      final snap = await _usersRef.child(userId).child('morrieBalance').get();
      final value = snap.value;
      if (value is num) return value.round();
    } catch (_) {
      // read 不可時は初期値扱い
    }
    return MorrieRules.defaultStartingBalance;
  }

  Future<void> ensureBalance(String userId) async {
    try {
      final ref = _usersRef.child(userId).child('morrieBalance');
      final snap = await ref.get();
      if (snap.exists) return;
      await _usersRef.child(userId).update({
        'morrieBalance': MorrieRules.defaultStartingBalance,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {
      // 初期化失敗は精算側でフォールバック
    }
  }

  /// シリーズ終了時にモリーを精算（二重適用防止付き）
  Future<MorrieSettlementResult?> applySeriesMorrie({
    required String roomId,
    required List<String> participantIds,
    required Map<String, int> finalPoints,
    required Map<String, String> displayNames,
    required int morrieRate,
  }) async {
    if (participantIds.length < 2 || morrieRate <= 0) return null;

    final roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
    final appliedSnap = await roomRef.child('seriesMorrieSettled').get();
    if (appliedSnap.value == true) return null;

    final humanUpdates = MorrieRules.humanBalanceUpdates(
      participantIds: participantIds,
      finalPoints: finalPoints,
      rate: morrieRate,
    );

    for (final id in participantIds) {
      if (BotLogic.isBot(id)) continue;
      await ensureBalance(id);
    }

    final ranked = RatingLogic.rankByPoints(participantIds, finalPoints);
    final rawDeltas = MorrieRules.rawMorrieDeltas(finalPoints, morrieRate);
    final morrieDetails = <String, dynamic>{};
    final rootUpdates = <String, dynamic>{
      'rooms/$roomId/seriesMorrieSettled': true,
    };
    final appliedDeltas = <String, int>{};
    final newBalances = <String, int>{};

    for (final entry in ranked) {
      final id = entry.id;
      final rawDelta = rawDeltas[id] ?? 0;
      if (BotLogic.isBot(id)) {
        morrieDetails[id] = {
          'rank': entry.rank,
          'points': entry.points,
          'morrieDelta': rawDelta,
          'morrieBalance': MorrieRules.botFixedBalance,
          'isBot': true,
        };
        continue;
      }

      final delta = humanUpdates[id] ?? 0;
      final current = await getBalance(id);
      final next = (current + delta).clamp(0, 1 << 30);
      appliedDeltas[id] = delta;
      newBalances[id] = next;

      morrieDetails[id] = {
        'rank': entry.rank,
        'points': entry.points,
        'morrieDelta': delta,
        'morrieBalance': next,
        'isBot': false,
      };

      rootUpdates['users/$id/morrieBalance'] = next;
      rootUpdates['users/$id/updatedAt'] = ServerValue.timestamp;
    }

    final botBalances = MorrieRules.botBalancesAfterSettlement(participantIds);
    if (botBalances.isNotEmpty) {
      rootUpdates['rooms/$roomId/botMorrieBalances'] = botBalances;
    }

    final summary = _buildSummary(
      ranked: ranked,
      displayNames: displayNames,
      deltas: appliedDeltas,
      rawDeltas: rawDeltas,
      morrieRate: morrieRate,
    );
    rootUpdates['rooms/$roomId/seriesMorrieSummary'] = summary;
    rootUpdates['rooms/$roomId/seriesMorrieDetails'] = morrieDetails;

    await FirebaseDatabase.instance.ref().update(rootUpdates);

    return MorrieSettlementResult(
      summary: summary,
      deltas: appliedDeltas,
      balances: newBalances,
    );
  }

  String _buildSummary({
    required List<({String id, int points, int rank})> ranked,
    required Map<String, String> displayNames,
    required Map<String, int> deltas,
    required Map<String, int> rawDeltas,
    required int morrieRate,
  }) {
    final lines = <String>['レート ×$morrieRate'];
    for (final entry in ranked) {
      final name = displayNames[entry.id] ?? entry.id;
      if (BotLogic.isBot(entry.id)) {
        final raw = rawDeltas[entry.id] ?? 0;
        lines.add(
          '$name: ${entry.points}点 → ${MorrieRules.botFixedBalance}モリー（変動 ${raw >= 0 ? '+' : ''}$raw、リセット）',
        );
        continue;
      }
      final delta = deltas[entry.id] ?? 0;
      final sign = delta >= 0 ? '+' : '';
      lines.add('$name: ${entry.points}点 → $sign$delta モリー');
    }
    return lines.join('\n');
  }
}
