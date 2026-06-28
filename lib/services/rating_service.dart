import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../logic/bot_logic.dart';
import '../logic/rating_logic.dart';
import '../logic/player_display_name.dart';
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
  static const int maxBotSlots = BotLogic.maxBotSlot;

  final DatabaseReference _ratingsRef =
      FirebaseDatabase.instance.ref('ratings');

  Map<String, dynamic> _defaultRatingPayload({String? displayName}) {
    final skill = RatingLogic.defaultSkillRating();
    return {
      'rating': RatingLogic.displayRating(skill),
      'mu': skill.mu,
      'sigma': skill.sigma,
      'gamesPlayed': 0,
      if (displayName != null && displayName.isNotEmpty) 'displayName': displayName,
    };
  }

  OpenSkillRating _parseSkillFromSnapshot(DataSnapshot snap) {
    if (!snap.exists || snap.value is! Map) {
      return RatingLogic.defaultSkillRating();
    }
    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    return OpenSkill.parseStored(
      muValue: data['mu'],
      sigmaValue: data['sigma'],
      ratingValue: data['rating'],
    );
  }

  Future<void> ensureBotRatings() async {
    for (var slot = 1; slot <= maxBotSlots; slot++) {
      final botId = BotLogic.botIdForSlot(slot);
      try {
        final snap = await _ratingsRef.child(botId).get();
        if (snap.exists) {
          await _migrateLegacyRatingIfNeeded(botId, snap);
          continue;
        }
        await _ratingsRef.child(botId).set({
          ..._defaultRatingPayload(),
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
      if (snap.exists) {
        await _migrateLegacyRatingIfNeeded(userId, snap);
        return;
      }
      await _ratingsRef.child(userId).set({
        ..._defaultRatingPayload(displayName: displayName),
        'isBot': false,
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

  Future<void> _migrateLegacyRatingIfNeeded(String playerId, DataSnapshot snap) async {
    if (snap.value is! Map) return;
    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    if (data['mu'] is num && data['sigma'] is num) return;

    final skill = OpenSkill.parseStored(
      muValue: data['mu'],
      sigmaValue: data['sigma'],
      ratingValue: data['rating'],
    );
    await _ratingsRef.child(playerId).update({
      'rating': RatingLogic.displayRating(skill),
      'mu': skill.mu,
      'sigma': skill.sigma,
    });
  }

  Future<OpenSkillRating> getSkillRating(String playerId) async {
    try {
      final snap = await _ratingsRef.child(playerId).get();
      return _parseSkillFromSnapshot(snap);
    } catch (_) {
      return RatingLogic.defaultSkillRating();
    }
  }

  Future<int> getRating(String playerId) async {
    final skill = await getSkillRating(playerId);
    return RatingLogic.displayRating(skill);
  }

  Future<double> getSigma(String playerId) async {
    final skill = await getSkillRating(playerId);
    return skill.sigma;
  }

  Future<Map<String, OpenSkillRating>> getSkillRatings(List<String> playerIds) async {
    final ratings = <String, OpenSkillRating>{};
    await Future.wait(playerIds.map((id) async {
      ratings[id] = await getSkillRating(id);
    }));
    return ratings;
  }

  Stream<List<RankingEntry>> watchRanking() {
    return _ratingsRef.onValue.map((event) => parseRankingSnapshot(event.snapshot.value));
  }

  static bool _isRetiredBotId(String id) => BotLogic.isRetiredBotId(id);

  static List<RankingEntry> parseRankingSnapshot(dynamic raw) {
    if (raw is! Map) return [];

    final entries = <RankingEntry>[];
    raw.forEach((key, value) {
      if (value is! Map) return;
      final id = key.toString();
      if (_isRetiredBotId(id)) return;
      final ratingValue = value['rating'];
      if (ratingValue is! num) return;

      final skill = OpenSkill.parseStored(
        muValue: value['mu'],
        sigmaValue: value['sigma'],
        ratingValue: ratingValue,
      );

      entries.add(RankingEntry(
        id: id,
        playerName: resolvePlayerName(id, value),
        rating: ratingValue.round(),
        sigma: skill.sigma,
        mu: skill.mu,
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
          sigma: entries[i].sigma,
          mu: entries[i].mu,
          gamesPlayed: entries[i].gamesPlayed,
          isBot: entries[i].isBot,
          rank: i + 1,
        ),
    ];
  }

  static String resolvePlayerName(String id, Map<dynamic, dynamic> data) {
    final playerName = data['playerName'];
    final displayName = data['displayName'];
    final raw = playerName is String && playerName.trim().isNotEmpty
        ? playerName.trim()
        : (displayName is String && displayName.trim().isNotEmpty
            ? displayName.trim()
            : null);
    return PlayerDisplayName.normalizeStoredPlayerName(id: id, rawName: raw);
  }

  static String _normalizeRatingPlayerName(String id, String? rawName) =>
      PlayerDisplayName.normalizeStoredPlayerName(id: id, rawName: rawName);

  Future<void> syncPlayerName(String userId, String playerName) async {
    final trimmed = _normalizeRatingPlayerName(userId, playerName);
    if (trimmed.isEmpty || trimmed == 'プレイヤー') return;
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

    final oldSkills = await getSkillRatings(participantIds);
    final updates = RatingLogic.computeSkillUpdates(
      oldRatings: oldSkills,
      playerIds: participantIds,
      finalPoints: finalPoints,
    );
    final ranked = RatingLogic.rankByPoints(participantIds, finalPoints);
    final summary = RatingLogic.buildSeriesSummary(
      ranked: ranked,
      oldRatings: oldSkills,
      updates: updates,
      displayNames: displayNames,
    );

    final newRatings = <String, int>{};
    final deltas = <String, int>{};
    final ratingDetails = <String, dynamic>{};

    for (final entry in ranked) {
      final id = entry.id;
      final update = updates[id];
      if (update == null) continue;

      final neuSkill = update.newRating;
      final delta = update.ratingDelta;
      final display = RatingLogic.displayRating(neuSkill);

      newRatings[id] = display;
      deltas[id] = delta;
      ratingDetails[id] = {
        'rank': entry.rank,
        'points': entry.points,
        'rating': display,
        'ratingDelta': delta,
        'mu': neuSkill.mu,
        'sigma': neuSkill.sigma,
      };
    }

    await roomRef.update({
      'seriesRatingApplied': true,
      'seriesRatingSummary': summary,
      'seriesRatingDetails': ratingDetails,
    });

    for (final entry in ranked) {
      final id = entry.id;
      final update = updates[id];
      if (update == null) continue;

      final neuSkill = update.newRating;
      final display = RatingLogic.displayRating(neuSkill);
      final ratingPayload = <String, dynamic>{
        'rating': display,
        'mu': neuSkill.mu,
        'sigma': neuSkill.sigma,
        'gamesPlayed': ServerValue.increment(1),
      };
      if (BotLogic.isBot(id)) {
        ratingPayload['isBot'] = true;
        final botName = BotLogic.botDisplayName(id);
        ratingPayload['displayName'] = botName;
        ratingPayload['playerName'] = botName;
      } else {
        ratingPayload['isBot'] = false;
        final name = _normalizeRatingPlayerName(id, displayNames[id]);
        if (name != 'プレイヤー') {
          ratingPayload['displayName'] = name;
          ratingPayload['playerName'] = name;
        }
      }
      try {
        await _ratingsRef.child(id).update(ratingPayload);
      } catch (_) {}
    }

    return RatingUpdateResult(
      summary: summary,
      newRatings: newRatings,
      deltas: deltas,
    );
  }
}
