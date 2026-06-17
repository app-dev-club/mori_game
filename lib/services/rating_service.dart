import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../logic/bot_logic.dart';
import '../logic/rating_logic.dart';
import '../models/ranking_entry.dart';

class RatingUpdateResult {
  final String summary;
  final Map<String, int> newRatings;
  final Map<String, int> deltas;

  const RatingUpdateResult({
    required this.summary,
    required this.newRatings,
    required this.deltas,
  });
}

/// Firebase Realtime Database 上のレート管理
class RatingService {
  static const int maxBotSlots = 8;

  final DatabaseReference _ratingsRef =
      FirebaseDatabase.instance.ref('ratings');

  Future<void> ensureBotRatings() async {
    for (var slot = 1; slot <= maxBotSlots; slot++) {
      final botId = BotLogic.botIdForSlot(slot);
      try {
        final snap = await _ratingsRef.child(botId).get();
        if (snap.exists) continue;
        await _ratingsRef.child(botId).set({
          'rating': RatingLogic.defaultRating,
          'gamesPlayed': 0,
          'isBot': true,
          'displayName': BotLogic.botDisplayName(botId),
        });
      } catch (_) {
        // 未ログインなどで書き込み不可の場合はスキップ（試合終了時に再試行）
      }
    }
  }

  Future<void> ensureUserRating(String userId, {String? displayName}) async {
    try {
      final snap = await _ratingsRef.child(userId).get();
      if (snap.exists) return;
      await _ratingsRef.child(userId).set({
        'rating': RatingLogic.defaultRating,
        'gamesPlayed': 0,
        'isBot': false,
        if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          'レート情報の保存が拒否されました。Firebase の database.rules をデプロイしてください。',
        );
      }
      rethrow;
    }
  }

  Future<int> getRating(String playerId) async {
    try {
      final snap = await _ratingsRef.child(playerId).child('rating').get();
      if (snap.value is num) return (snap.value as num).round();
    } catch (_) {
      // 未ログインで read 不可の場合など
    }
    return RatingLogic.defaultRating;
  }

  Future<Map<String, int>> getRatings(List<String> playerIds) async {
    final ratings = <String, int>{};
    await Future.wait(playerIds.map((id) async {
      ratings[id] = await getRating(id);
    }));
    return ratings;
  }

  Stream<List<RankingEntry>> watchRanking() {
    return _ratingsRef.onValue.map((event) => parseRankingSnapshot(event.snapshot.value));
  }

  static List<RankingEntry> parseRankingSnapshot(dynamic raw) {
    if (raw is! Map) return [];

    final entries = <RankingEntry>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      final id = key.toString();
      final ratingValue = value['rating'];
      if (ratingValue is! num) return;

      entries.add(RankingEntry(
        id: id,
        playerName: resolvePlayerName(id, value),
        rating: ratingValue.round(),
        gamesPlayed: value['gamesPlayed'] is num ? (value['gamesPlayed'] as num).round() : 0,
        isBot: value['isBot'] == true || BotLogic.isBot(id),
        rank: 0,
      ));
    });

    entries.sort((a, b) {
      final byRating = b.rating.compareTo(a.rating);
      if (byRating != 0) return byRating;
      return a.playerName.compareTo(b.playerName);
    });

    return [
      for (var i = 0; i < entries.length; i++)
        RankingEntry(
          id: entries[i].id,
          playerName: entries[i].playerName,
          rating: entries[i].rating,
          gamesPlayed: entries[i].gamesPlayed,
          isBot: entries[i].isBot,
          rank: i + 1,
        ),
    ];
  }

  static String resolvePlayerName(String id, Map<dynamic, dynamic> data) {
    final playerName = data['playerName'];
    if (playerName is String && playerName.trim().isNotEmpty) {
      return playerName.trim();
    }
    if (BotLogic.isBot(id) || data['isBot'] == true) {
      return BotLogic.botDisplayName(id);
    }
    final displayName = data['displayName'];
    if (displayName is String && displayName.trim().isNotEmpty) {
      return displayName.trim();
    }
    return 'プレイヤー';
  }

  Future<void> syncPlayerName(String userId, String playerName) async {
    final trimmed = playerName.trim();
    if (trimmed.isEmpty) return;
    try {
      await ensureUserRating(userId);
      await _ratingsRef.child(userId).update({'playerName': trimmed});
    } catch (_) {
      // ランキング表示用の同期失敗は本体保存を妨げない
    }
  }

  /// 規定試合終了時に同室メンバーのレートを更新（二重適用防止付き）
  Future<RatingUpdateResult?> applySeriesRating({
    required String roomId,
    required List<String> participantIds,
    required Map<String, int> finalPoints,
    required Map<String, String> displayNames,
  }) async {
    if (participantIds.length < 2) return null;

    final roomRef = FirebaseDatabase.instance.ref('rooms/$roomId');
    final appliedSnap = await roomRef.child('seriesRatingApplied').get();
    if (appliedSnap.value == true) return null;

    await ensureBotRatings();

    for (final id in participantIds) {
      if (BotLogic.isBot(id)) continue;
      await ensureUserRating(id, displayName: displayNames[id]);
    }

    final oldRatings = await getRatings(participantIds);
    final deltas = RatingLogic.computeDeltas(oldRatings, participantIds, finalPoints);
    final ranked = RatingLogic.rankByPoints(participantIds, finalPoints);
    final summary = RatingLogic.buildSeriesSummary(
      ranked: ranked,
      oldRatings: oldRatings,
      deltas: deltas,
      displayNames: displayNames,
    );

    final newRatings = <String, int>{};
    final rootUpdates = <String, dynamic>{
      'rooms/$roomId/seriesRatingApplied': true,
      'rooms/$roomId/seriesRatingSummary': summary,
    };

    for (final id in participantIds) {
      final old = oldRatings[id] ?? RatingLogic.defaultRating;
      final delta = deltas[id] ?? 0;
      final neu = old + delta;
      newRatings[id] = neu;
      rootUpdates['ratings/$id/rating'] = neu;
      rootUpdates['ratings/$id/gamesPlayed'] = ServerValue.increment(1);
      if (BotLogic.isBot(id)) {
        rootUpdates['ratings/$id/isBot'] = true;
        final botName = BotLogic.botDisplayName(id);
        rootUpdates['ratings/$id/displayName'] = botName;
        rootUpdates['ratings/$id/playerName'] = botName;
      } else {
        rootUpdates['ratings/$id/isBot'] = false;
        final name = displayNames[id];
        if (name != null && name.isNotEmpty) {
          rootUpdates['ratings/$id/displayName'] = name;
          rootUpdates['ratings/$id/playerName'] = name;
        }
      }
    }

    await FirebaseDatabase.instance.ref().update(rootUpdates);

    return RatingUpdateResult(
      summary: summary,
      newRatings: newRatings,
      deltas: deltas,
    );
  }
}
