import 'package:firebase_database/firebase_database.dart';

import '../logic/bot_logic.dart';
import '../logic/morrie_rules.dart';
import '../logic/rating_logic.dart';

import '../models/morrie_ranking_entry.dart';

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
  final DatabaseReference _morrieRankingsRef =
      FirebaseDatabase.instance.ref('morrieRankings');

  Future<String?> _getStoredPlayerName(String userId) async {
    try {
      final snap = await _usersRef.child(userId).child('playerName').get();
      final value = snap.value;
      if (value is String && value.trim().isNotEmpty) return value.trim();
    } catch (_) {}
    return null;
  }

  Future<void> syncRankingEntry(
    String userId, {
    required int morrieBalance,
    String? playerName,
  }) async {
    final name = playerName?.trim().isNotEmpty == true
        ? playerName!.trim()
        : (await _getStoredPlayerName(userId)) ?? 'プレイヤー';
    try {
      await _morrieRankingsRef.child(userId).set({
        'playerName': name,
        'morrieBalance': morrieBalance,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (_) {
      // ランキング同期失敗は本体残高を妨げない
    }
  }

  Stream<List<MorrieRankingEntry>> watchMorrieRanking() {
    return _morrieRankingsRef.onValue.map(
      (event) => parseMorrieRankingSnapshot(event.snapshot.value),
    );
  }

  Stream<Map<String, int>> watchMorrieBalanceMap() {
    return _morrieRankingsRef.onValue.map(
      (event) => parseMorrieBalanceMap(event.snapshot.value),
    );
  }

  static Map<String, int> parseMorrieBalanceMap(dynamic raw) {
    if (raw is! Map) return {};

    final balances = <String, int>{};
    raw.forEach((key, value) {
      if (value is! Map) return;
      final balanceValue = value['morrieBalance'];
      if (balanceValue is! num) return;
      balances[key.toString()] = balanceValue.round();
    });
    return balances;
  }

  /// ルーム参加者のモリー残高合計（Bot は固定値）
  static int totalMorrieForPlayers(
    Iterable<String> playerIds,
    Map<String, int> balanceMap,
  ) {
    var total = 0;
    for (final id in playerIds) {
      if (BotLogic.isBot(id)) {
        total += MorrieRules.botFixedBalance;
      } else {
        total += balanceMap[id] ?? MorrieRules.defaultStartingBalance;
      }
    }
    return total;
  }

  static List<MorrieRankingEntry> parseMorrieRankingSnapshot(dynamic raw) {
    if (raw is! Map) return [];

    final entries = <MorrieRankingEntry>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      final id = key.toString();
      if (BotLogic.isBot(id)) return;
      final balanceValue = value['morrieBalance'];
      if (balanceValue is! num) return;

      final playerName = value['playerName'];
      entries.add(
        MorrieRankingEntry(
          id: id,
          playerName: playerName is String && playerName.trim().isNotEmpty
              ? playerName.trim()
              : 'プレイヤー',
          morrieBalance: balanceValue.round(),
          rank: 0,
        ),
      );
    });

    entries.sort((a, b) {
      final byBalance = b.morrieBalance.compareTo(a.morrieBalance);
      if (byBalance != 0) return byBalance;
      return a.playerName.compareTo(b.playerName);
    });

    return [
      for (var i = 0; i < entries.length; i++)
        MorrieRankingEntry(
          id: entries[i].id,
          playerName: entries[i].playerName,
          morrieBalance: entries[i].morrieBalance,
          rank: i + 1,
        ),
    ];
  }

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
      await syncRankingEntry(
        userId,
        morrieBalance: MorrieRules.defaultStartingBalance,
      );
    } catch (_) {
      // 初期化失敗は精算側でフォールバック
    }
  }

  /// 広告視聴報酬でモリーを加算する
  Future<int> grantAdReward(String userId) async {
    await ensureBalance(userId);
    final current = await getBalance(userId);
    final next = current + MorrieRules.adRewardAmount;
    await _usersRef.child(userId).update({
      'morrieBalance': next,
      'updatedAt': ServerValue.timestamp,
    });
    await syncRankingEntry(userId, morrieBalance: next);
    return next;
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

    for (final id in participantIds) {
      if (BotLogic.isBot(id)) continue;
      await ensureBalance(id);
    }

    final humanBalances = <String, int>{};
    for (final id in participantIds) {
      if (BotLogic.isBot(id)) continue;
      humanBalances[id] = await getBalance(id);
    }

    final humanUpdates = MorrieRules.humanBalanceUpdates(
      participantIds: participantIds,
      finalPoints: finalPoints,
      rate: morrieRate,
    );

    final ranked = RatingLogic.rankByPoints(participantIds, finalPoints);
    final rawDeltas = MorrieRules.rawMorrieDeltas(finalPoints, morrieRate);
    final morrieDetails = <String, dynamic>{};
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
      final current = humanBalances[id] ?? await getBalance(id);
      final next = current + delta;
      appliedDeltas[id] = delta;
      newBalances[id] = next;

      morrieDetails[id] = {
        'rank': entry.rank,
        'points': entry.points,
        'morrieDelta': delta,
        'morrieBalance': next,
        'isBot': false,
      };
    }

    final botBalances = MorrieRules.botBalancesAfterSettlement(participantIds);

    final summary = _buildSummary(
      ranked: ranked,
      displayNames: displayNames,
      deltas: appliedDeltas,
      rawDeltas: rawDeltas,
      morrieRate: morrieRate,
    );

    final roomUpdates = <String, dynamic>{
      'seriesMorrieSettled': true,
      'seriesMorrieSummary': summary,
      'seriesMorrieDetails': morrieDetails,
    };
    if (botBalances.isNotEmpty) {
      roomUpdates['botMorrieBalances'] = botBalances;
    }
    await roomRef.update(roomUpdates);

    for (final entry in ranked) {
      final id = entry.id;
      if (BotLogic.isBot(id)) continue;
      final next = newBalances[id];
      if (next == null) continue;
      final name = displayNames[id]?.trim().isNotEmpty == true
          ? displayNames[id]!.trim()
          : 'プレイヤー';
      try {
        await _usersRef.child(id).update({
          'morrieBalance': next,
          'updatedAt': ServerValue.timestamp,
        });
        await syncRankingEntry(id, morrieBalance: next, playerName: name);
        await roomRef.child('morrieClaimed/$id').set(true);
        await FirebaseDatabase.instance
            .ref('userMorriePending/$id/$roomId')
            .remove();
      } catch (_) {
        await FirebaseDatabase.instance.ref('userMorriePending/$id/$roomId').set({
          'morrieBalance': next,
          'playerName': name,
          'settledAt': ServerValue.timestamp,
        });
      }
    }

    return MorrieSettlementResult(
      summary: summary,
      deltas: appliedDeltas,
      balances: newBalances,
    );
  }

  /// ルーム精算の未反映モリーを自分のアカウントへ適用する
  Future<bool> claimPendingMorrieForUser(String userId) async {
    final pendingRef = FirebaseDatabase.instance.ref('userMorriePending/$userId');
    final snap = await pendingRef.get();
    if (!snap.exists || snap.value is! Map) return false;

    var claimed = false;
    final entries = Map<dynamic, dynamic>.from(snap.value as Map);
    for (final entry in entries.entries) {
      final roomId = entry.key.toString();
      if (entry.value is! Map) continue;
      final data = Map<dynamic, dynamic>.from(entry.value as Map);
      final balance = data['morrieBalance'];
      if (balance is! num) continue;
      final next = balance.round();
      final name = data['playerName']?.toString();
      try {
        await _usersRef.child(userId).update({
          'morrieBalance': next,
          'updatedAt': ServerValue.timestamp,
        });
        await syncRankingEntry(
          userId,
          morrieBalance: next,
          playerName: name,
        );
        await FirebaseDatabase.instance.ref('rooms/$roomId/morrieClaimed/$userId').set(true);
        await pendingRef.child(roomId).remove();
        claimed = true;
      } catch (_) {}
    }
    return claimed;
  }

  /// 特定ルームの精算結果を自分のアカウントへ適用する（復帰時）
  Future<bool> claimMorrieFromRoom(String roomId, String userId) async {
    final roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
    if (roomRef.path.isEmpty) return false;
    final settled = (await roomRef.child('seriesMorrieSettled').get()).value == true;
    if (!settled) return false;
    if ((await roomRef.child('morrieClaimed/$userId').get()).value == true) {
      return false;
    }
    final detailSnap = await roomRef.child('seriesMorrieDetails/$userId').get();
    if (!detailSnap.exists || detailSnap.value is! Map) return false;
    final detail = Map<dynamic, dynamic>.from(detailSnap.value as Map);
    final balance = detail['morrieBalance'];
    if (balance is! num) return false;
    final next = balance.round();
    try {
      await _usersRef.child(userId).update({
        'morrieBalance': next,
        'updatedAt': ServerValue.timestamp,
      });
      await syncRankingEntry(userId, morrieBalance: next);
      await roomRef.child('morrieClaimed/$userId').set(true);
      await FirebaseDatabase.instance.ref('userMorriePending/$userId/$roomId').remove();
      return true;
    } catch (_) {
      return false;
    }
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
