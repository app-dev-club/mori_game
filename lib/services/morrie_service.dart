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
    final name = playerName?.trim().isNotEmpty == true
        ? playerName!.trim()
        : BotLogic.botDisplayName(botId);
    await syncRankingEntry(botId, morrieBalance: morrieBalance, playerName: name);
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

  Future<Map<String, int>> _loadParticipantMorrieBalances(
    DatabaseReference roomRef,
    Iterable<String> participantIds,
  ) async {
    final ids = participantIds.toList();
    final balances = await _loadBotMorrieBalances(
      roomRef,
      ids.where(BotLogic.isBot),
    );
    for (final id in ids) {
      if (BotLogic.isBot(id)) continue;
      await ensureBalance(id);
      balances[id] = await getBalance(id);
    }
    return balances;
  }

  ({Map<String, int> deltas, Map<String, int> balances}) _buildFullMatchMorrieDisplay({
    required List<String> participantIds,
    required Map<String, int> moveDeltas,
    required Map<String, int> afterMoveBalances,
    required Map<String, int> beforeBalances,
  }) {
    final deltas = <String, int>{};
    final balances = <String, int>{};
    for (final id in participantIds) {
      deltas[id] = moveDeltas[id] ?? 0;
      balances[id] = afterMoveBalances[id] ??
          beforeBalances[id] ??
          MorrieRules.resolvePlayerBalance(id, beforeBalances);
    }
    return (deltas: deltas, balances: balances);
  }

  /// バースト時にモリーを減算（2点 × レート、二重適用防止付き）
  Future<MoriMorrieTransferResult?> applyBurstMorrieDeduction({
    required String roomId,
    required String burstPlayerId,
    required int morrieRate,
    required Map<String, String> displayNames,
    required List<String> participantIds,
  }) async {
    if (morrieRate <= 0) return null;

    final roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
    if ((await roomRef.child('lastMatchMorrieApplied').get()).value == true) {
      return null;
    }

    final playerBalances = await _loadParticipantMorrieBalances(
      roomRef,
      participantIds,
    );

    final deduction = MorrieRules.computeBurstMorrieDeduction(
      rate: morrieRate,
      burstPlayerId: burstPlayerId,
      playerBalances: playerBalances,
    );
    if (deduction.actualMorrie <= 0 && !deduction.morrieBurst) {
      await roomRef.update({'lastMatchMorrieApplied': true});
      return null;
    }

    final newBalances = <String, int>{};
    final botBalanceUpdates = <String, int>{};
    for (final entry in deduction.deltas.entries) {
      final id = entry.key;
      if (BotLogic.isBot(id)) {
        final current = playerBalances[id] ?? MorrieRules.botFixedBalance;
        final next = (current + entry.value).clamp(0, 1 << 30);
        botBalanceUpdates[id] = next;
        newBalances[id] = next;
        await syncBotRankingEntry(
          id,
          morrieBalance: next,
          playerName: displayNames[id],
        );
        continue;
      }

      final current = playerBalances[id] ?? await getBalance(id);
      final next = (current + entry.value).clamp(0, 1 << 30);
      newBalances[id] = next;
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

    final seriesSnap = await roomRef.child('playerMorrieSeriesDeltas').get();
    final seriesDeltas = seriesSnap.value is Map
        ? Map<String, int>.from(
            (seriesSnap.value as Map).map(
              (k, v) => MapEntry(k.toString(), v is int ? v : (v as num).round()),
            ),
          )
        : <String, int>{};
    for (final entry in deduction.deltas.entries) {
      seriesDeltas[entry.key] = (seriesDeltas[entry.key] ?? 0) + entry.value;
    }

    final summary = MorrieRules.describeBurstMorrieDeduction(
      burstPlayerName: displayNames[burstPlayerId] ?? burstPlayerId,
      burstPlayerId: burstPlayerId,
      rate: morrieRate,
      deduction: deduction,
    );

    final display = _buildFullMatchMorrieDisplay(
      participantIds: participantIds,
      moveDeltas: deduction.deltas,
      afterMoveBalances: newBalances,
      beforeBalances: playerBalances,
    );

    final roomUpdates = <String, dynamic>{
      'lastMatchMorrieApplied': true,
      'lastMatchMorrieDeltas': display.deltas,
      'lastMatchMorrieSummary': summary,
      'playerMorrieSeriesDeltas': seriesDeltas,
      'lastMatchMorrieBalances': display.balances,
    };
    if (deduction.morrieBurst) {
      roomUpdates['morrieBurstPlayerId'] = burstPlayerId;
    }
    for (final entry in botBalanceUpdates.entries) {
      roomUpdates['botMorrieBalances/${entry.key}'] = entry.value;
    }
    await roomRef.update(roomUpdates);

    return MoriMorrieTransferResult(
      summary: summary,
      deltas: display.deltas,
      balances: display.balances,
      morrieBurst: deduction.morrieBurst,
    );
  }

  /// もり成立時にモリーを loser → winner へ移動（二重適用防止付き）
  Future<MoriMorrieTransferResult?> applyMatchMorrieTransfer({
    required String roomId,
    required String winnerId,
    required String loserId,
    required int pointDelta,
    required int morrieRate,
    required Map<String, String> displayNames,
    required List<String> participantIds,
  }) async {
    if (morrieRate <= 0 || pointDelta <= 0) return null;

    final roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
    if ((await roomRef.child('lastMatchMorrieApplied').get()).value == true) {
      return null;
    }

    final playerBalances = await _loadParticipantMorrieBalances(
      roomRef,
      participantIds,
    );

    final transfer = MorrieRules.computeMoriMorrieTransfer(
      pointDelta: pointDelta,
      rate: morrieRate,
      winnerId: winnerId,
      loserId: loserId,
      playerBalances: playerBalances,
    );
    if (transfer.actualMorrie <= 0) {
      await roomRef.update({'lastMatchMorrieApplied': true});
      return null;
    }

    final newBalances = <String, int>{};
    final botBalanceUpdates = <String, int>{};
    for (final entry in transfer.deltas.entries) {
      final id = entry.key;
      if (BotLogic.isBot(id)) {
        final current = playerBalances[id] ?? MorrieRules.botFixedBalance;
        final next = (current + entry.value).clamp(0, 1 << 30);
        botBalanceUpdates[id] = next;
        newBalances[id] = next;
        await syncBotRankingEntry(
          id,
          morrieBalance: next,
          playerName: displayNames[id],
        );
        continue;
      }

      final current = playerBalances[id] ?? await getBalance(id);
      final next = (current + entry.value).clamp(0, 1 << 30);
      newBalances[id] = next;
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

    final seriesSnap = await roomRef.child('playerMorrieSeriesDeltas').get();
    final seriesDeltas = seriesSnap.value is Map
        ? Map<String, int>.from(
            (seriesSnap.value as Map).map(
              (k, v) => MapEntry(k.toString(), v is int ? v : (v as num).round()),
            ),
          )
        : <String, int>{};
    for (final entry in transfer.deltas.entries) {
      seriesDeltas[entry.key] = (seriesDeltas[entry.key] ?? 0) + entry.value;
    }

    final summary = MorrieRules.describeMoriMorrieTransfer(
      winnerName: displayNames[winnerId] ?? winnerId,
      loserName: displayNames[loserId] ?? loserId,
      loserId: loserId,
      pointDelta: pointDelta,
      rate: morrieRate,
      transfer: transfer,
    );

    final display = _buildFullMatchMorrieDisplay(
      participantIds: participantIds,
      moveDeltas: transfer.deltas,
      afterMoveBalances: newBalances,
      beforeBalances: playerBalances,
    );

    final roomUpdates = <String, dynamic>{
      'lastMatchMorrieApplied': true,
      'lastMatchMorrieDeltas': display.deltas,
      'lastMatchMorrieSummary': summary,
      'playerMorrieSeriesDeltas': seriesDeltas,
      'lastMatchMorrieBalances': display.balances,
    };
    if (transfer.morrieBurst) {
      roomUpdates['morrieBurstPlayerId'] = loserId;
    }
    for (final entry in botBalanceUpdates.entries) {
      roomUpdates['botMorrieBalances/${entry.key}'] = entry.value;
    }
    await roomRef.update(roomUpdates);

    return MoriMorrieTransferResult(
      summary: summary,
      deltas: display.deltas,
      balances: display.balances,
      morrieBurst: transfer.morrieBurst,
    );
  }

  /// 飛び発生ボットへ試合終了後に回復モリーを付与（人間には付与しない）
  Future<bool> applyMorrieBurstRecoveryIfNeeded({
    required String roomId,
    required Map<String, String> displayNames,
  }) async {
    final roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
    final snap = await roomRef.get();
    if (!snap.exists || snap.value is! Map) return false;

    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    final burstId = data['morrieBurstPlayerId']?.toString();
    if (burstId == null || burstId.isEmpty) return false;
    if (data['morrieBurstRecoveryApplied'] == true) return false;

    if (!BotLogic.isBot(burstId)) {
      await roomRef.update({'morrieBurstRecoveryApplied': true});
      return false;
    }

    final amount = MorrieRules.burstRecoveryAmount;
    final updates = <String, dynamic>{
      'morrieBurstRecoveryApplied': true,
    };

    final botSnap = await roomRef.child('botMorrieBalances/$burstId').get();
    final current = botSnap.value is num
        ? (botSnap.value as num).round()
        : await getBotBalance(burstId);
    final next = current + amount;
    updates['botMorrieBalances/$burstId'] = next;
    await syncBotRankingEntry(
      burstId,
      morrieBalance: next,
      playerName: displayNames[burstId],
    );

    final summary = data['lastMatchMorrieSummary']?.toString() ?? '';
    if (summary.isNotEmpty) {
      updates['lastMatchMorrieSummary'] =
          '$summary\n（${_displayNameOrId(burstId, displayNames)} に回復$amountモリー付与）';
    }

    await roomRef.update(updates);
    return true;
  }

  String _displayNameOrId(String id, Map<String, String> displayNames) =>
      displayNames[id] ?? id;

  /// シリーズ終了時: モリー表示用サマリーのみ確定（残高は試合ごとに反映済み）
  Future<MorrieSettlementResult?> finalizeSeriesMorrieDisplay({
    required String roomId,
    required List<String> participantIds,
    required Map<String, int> finalPoints,
    required Map<String, String> displayNames,
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
    final seriesSnap = await roomRef.child('playerMorrieSeriesDeltas').get();
    final seriesDeltas = seriesSnap.value is Map
        ? Map<String, int>.from(
            (seriesSnap.value as Map).map(
              (k, v) => MapEntry(k.toString(), v is int ? v : (v as num).round()),
            ),
          )
        : <String, int>{};

    final morrieDetails = <String, dynamic>{};
    final summaryLines = <String>['シリーズ合計モリー変動'];

    for (final entry in ranked) {
      final id = entry.id;
      final delta = seriesDeltas[id] ?? 0;
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
      );

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
}
