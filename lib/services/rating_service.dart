import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../logic/bot_logic.dart';
import '../logic/rating_logic.dart';

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
        rootUpdates['ratings/$id/displayName'] = BotLogic.botDisplayName(id);
      } else {
        rootUpdates['ratings/$id/isBot'] = false;
        final name = displayNames[id];
        if (name != null && name.isNotEmpty) {
          rootUpdates['ratings/$id/displayName'] = name;
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
