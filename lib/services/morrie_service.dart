import 'package:firebase_database/firebase_database.dart';

import '../logic/bot_logic.dart';
import '../logic/morrie_rules.dart';
import '../logic/player_display_name.dart';
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

class MoriMorrieTransferResult {
  final String summary;
  final Map<String, int> deltas;
  final Map<String, int> balances;
  final bool morrieBurst;

  const MoriMorrieTransferResult({
    required this.summary,
    required this.deltas,
    required this.balances,
    required this.morrieBurst,
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

  Future<void> ensureBotMorrieRankings() async {
    for (var slot = 1; slot <= BotLogic.maxBotSlot; slot++) {
      final botId = BotLogic.botIdForSlot(slot);
      try {
        final snap = await _morrieRankingsRef.child(botId).get();
        if (snap.exists) continue;
        await syncBotRankingEntry(
          botId,
          morrieBalance: MorrieRules.botFixedBalance,
        );
      } catch (_) {
        // 未ログインやルール未デプロイ時はスキップ（次回表示時に再試行）
      }
    }
  }

  Future<void> syncBotRankingEntry(
    String botId, {
    required int morrieBalance,
    String? playerName,
  }) async {
    if (!BotLogic.isBot(botId)) return;
    await syncRankingEntry(
      botId,
      morrieBalance: morrieBalance,
      playerName: BotLogic.botDisplayName(botId),
    );
  }

  Future<void> syncRankingEntry(
    String userId, {
    required int morrieBalance,
    String? playerName,
  }) async {
    final name = BotLogic.isBot(userId)
        ? BotLogic.botDisplayName(userId)
        : PlayerDisplayName.normalizeStoredPlayerName(
            id: userId,
            rawName: playerName?.trim().isNotEmpty == true
                ? playerName!.trim()
                : await _getStoredPlayerName(userId),
          );
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
        total += balanceMap[id] ?? MorrieRules.botFixedBalance;
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
      final balanceValue = value['morrieBalance'];
      if (balanceValue is! num) return;

      final playerName = value['playerName'];
      entries.add(
        MorrieRankingEntry(
          id: id,
          playerName: PlayerDisplayName.normalizeStoredPlayerName(
            id: id,
            rawName: playerName is String ? playerName : null,
          ),
          morrieBalance: balanceValue.round(),
          rank: 0,
          isBot: BotLogic.isBot(id),
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
          isBot: entries[i].isBot,
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

  /// users/ の残高をリアルタイム監視（手動補填や CF 反映をそのまま表示）
  Stream<int> watchBalance(String userId) {
    return _usersRef.child(userId).child('morrieBalance').onValue.map((event) {
      final value = event.snapshot.value;
      if (value is num) return value.round();
      return MorrieRules.defaultStartingBalance;
    });
  }

  /// 公開ランキングを users/ の正残高に合わせる（users は上書きしない）
  Future<void> syncRankingFromUserBalance(
    String userId, {
    String? playerName,
  }) async {
    final balance = await getBalance(userId);
    await syncRankingEntry(
      userId,
      morrieBalance: balance,
      playerName: playerName,
    );
  }

  /// ボットのグローバル所持モリー（初回のみ botFixedBalance）
  Future<int> getBotBalance(String botId) async {
    if (!BotLogic.isBot(botId)) {
      return MorrieRules.defaultStartingBalance;
    }
    try {
      final snap = await _morrieRankingsRef.child(botId).child('morrieBalance').get();
      final value = snap.value;
      if (value is num) return value.round().clamp(0, 1 << 30);
    } catch (_) {
      // 読み取り不可時は初期値扱い
    }
    return MorrieRules.botFixedBalance;
  }

  /// ランキングから複数プレイヤーのモリー残高を取得（他ユーザーの users/ は読めないため）
  Future<Map<String, int>> getRankingBalances(Iterable<String> userIds) async {
    final balances = <String, int>{};
    for (final userId in userIds) {
      if (BotLogic.isBot(userId)) continue;
      try {
        final snap = await _morrieRankingsRef.child(userId).get();
        final value = snap.value;
        if (value is Map) {
          final balance = value['morrieBalance'];
          if (balance is num) {
            balances[userId] = balance.round();
          }
        }
      } catch (_) {
        // 読み取り不可はスキップ
      }
    }
    return balances;
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

  Future<Map<String, int>> _loadBotMorrieBalances(
    DatabaseReference roomRef,
    Iterable<String> botIds,
  ) async {
    final snap = await roomRef.child('botMorrieBalances').get();
    final stored = snap.value is Map
        ? Map<String, int>.from(
            (snap.value as Map).map(
              (k, v) => MapEntry(k.toString(), v is int ? v : (v as num).round()),
            ),
          )
        : <String, int>{};
    final balances = <String, int>{};
    for (final id in botIds) {
      if (stored.containsKey(id)) {
        balances[id] = stored[id]!;
      } else {
        balances[id] = await getBotBalance(id);
      }
    }
    return balances;
  }

  /// 試合終了時のモリー適用は Cloud Functions が行う（クライアントから残高を書き換えない）
  Future<MoriMorrieTransferResult?> applyBurstMorrieDeduction({
    required String roomId,
    required String burstPlayerId,
    required int morrieRate,
    required Map<String, String> displayNames,
    required List<String> participantIds,
  }) async {
    return null;
  }

  /// もり成立時のモリー移動は Cloud Functions が行う（クライアントから残高を書き換えない）
  Future<MoriMorrieTransferResult?> applyMatchMorrieTransfer({
    required String roomId,
    required String winnerId,
    required String loserId,
    required int pointDelta,
    required int morrieRate,
    required Map<String, String> displayNames,
    required List<String> participantIds,
  }) async {
    return null;
  }

  /// 飛び発生ボットへの回復は Cloud Functions が行う
  Future<bool> applyMorrieBurstRecoveryIfNeeded({
    required String roomId,
    required Map<String, String> displayNames,
  }) async {
    return false;
  }

  /// シリーズ終了時: モリー表示用サマリーのみ確定（残高は試合ごとに反映済み）
  Future<MorrieSettlementResult?> finalizeSeriesMorrieDisplay({
    required String roomId,
    required List<String> participantIds,
    required Map<String, int> finalPoints,
    required Map<String, String> displayNames,
    required int morrieRate,
  }) async {
    if (participantIds.length < 2) return null;

    final roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
    final appliedSnap = await roomRef.child('seriesMorrieSettled').get();
    if (appliedSnap.value == true) return null;

    final ranked = RatingLogic.rankByPoints(participantIds, finalPoints);
    final botBalances = await _loadBotMorrieBalances(
      roomRef,
      participantIds.where(BotLogic.isBot),
    );

    final morrieDetails = <String, dynamic>{};
    final summaryLines = <String>['シリーズ合計モリー変動'];
    final seriesDeltas = <String, int>{};

    for (final entry in ranked) {
      final id = entry.id;
      final delta = MorrieRules.moriMorrieAmount(entry.points, morrieRate);
      seriesDeltas[id] = delta;
      if (BotLogic.isBot(id)) {
        morrieDetails[id] = {
          'rank': entry.rank,
          'points': entry.points,
          'morrieDelta': delta,
          'morrieBalance': botBalances[id] ?? MorrieRules.botFixedBalance,
          'isBot': true,
        };
        continue;
      }

      final balance = await getBalance(id);
      morrieDetails[id] = {
        'rank': entry.rank,
        'points': entry.points,
        'morrieDelta': delta,
        'morrieBalance': balance,
        'isBot': false,
      };
      if (delta != 0) {
        final sign = delta >= 0 ? '+' : '';
        summaryLines.add('${displayNames[id] ?? id}: $sign$delta モリー');
      }
    }

    final roomUpdates = <String, dynamic>{
      'seriesMorrieSettled': true,
      'seriesMorrieSummary': summaryLines.join('\n'),
      'seriesMorrieDetails': morrieDetails,
    };
    await roomRef.update(roomUpdates);

    return MorrieSettlementResult(
      summary: summaryLines.join('\n'),
      deltas: seriesDeltas,
      balances: {
        for (final id in participantIds)
          if (!BotLogic.isBot(id)) id: await getBalance(id),
      },
    );
  }

  Future<MorrieSettlementResult?> applySeriesMorrie({
    required String roomId,
    required List<String> participantIds,
    required Map<String, int> finalPoints,
    required Map<String, String> displayNames,
    required int morrieRate,
  }) =>
      finalizeSeriesMorrieDisplay(
        roomId: roomId,
        participantIds: participantIds,
        finalPoints: finalPoints,
        displayNames: displayNames,
        morrieRate: morrieRate,
      );

  /// 旧 pending キューを削除する（残高は users/ が正。上書きしない）
  Future<bool> clearStaleMorriePending(String userId) async {
    final pendingRef = FirebaseDatabase.instance.ref('userMorriePending/$userId');
    final snap = await pendingRef.get();
    if (!snap.exists || snap.value is! Map) return false;

    var cleared = false;
    final entries = Map<dynamic, dynamic>.from(snap.value as Map);
    for (final entry in entries.entries) {
      try {
        await pendingRef.child(entry.key.toString()).remove();
        cleared = true;
      } catch (_) {}
    }
    return cleared;
  }

  /// ルーム精算済みフラグのみ同期（残高は CF / 手動補填の users/ を正とする）
  Future<bool> claimMorrieFromRoom(String roomId, String userId) async {
    final roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
    if (roomRef.path.isEmpty) return false;
    if ((await roomRef.child('morrieClaimed/$userId').get()).value == true) {
      return false;
    }
    final settled = (await roomRef.child('seriesMorrieSettled').get()).value == true;
    if (!settled) return false;

    try {
      await roomRef.child('morrieClaimed/$userId').set(true);
      await FirebaseDatabase.instance.ref('userMorriePending/$userId/$roomId').remove();
      return true;
    } catch (_) {
      return false;
    }
  }
}
