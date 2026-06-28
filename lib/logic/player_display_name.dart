import 'bot_logic.dart';
import '../models/ranking_entry.dart';

/// 画面上に表示するプレイヤー名を解決する
class PlayerDisplayName {
  static final RegExp _youPrefixPattern = RegExp(r'^あなた(?:（([^）]*)）)?$');
  static const _botSuffixes = ['（Bot）', '(Bot)', '（bot）', '(bot)'];

  /// ランキングDB保存・表示用。UI用ラベル（あなた/Bot接尾辞等）を除去する。
  static String normalizeStoredPlayerName({
    required String id,
    String? rawName,
  }) {
    if (BotLogic.isBot(id)) {
      return BotLogic.botDisplayName(id);
    }

    var name = rawName?.trim() ?? '';
    final youMatch = _youPrefixPattern.firstMatch(name);
    if (youMatch != null) {
      name = youMatch.group(1)?.trim() ?? '';
    }

    for (final suffix in _botSuffixes) {
      if (name.endsWith(suffix)) {
        name = name.substring(0, name.length - suffix.length).trim();
      }
    }

    if (name.isEmpty) return 'プレイヤー';
    return name;
  }

  static String resolve({
    required String? playerId,
    required List<String> playerIds,
    required String myId,
    required Map<String, String> playerNames,
    String? hostId,
    bool hideOpponentNames = false,
    Set<String> afkPlayerIds = const {},
  }) {
    if (playerId == null) return '';
    if (playerId == 'system') return '山札';
    if (playerId == myId) {
      final myName = playerNames[myId];
      if (myName != null && myName.isNotEmpty) return 'あなた（$myName）';
      return 'あなた';
    }

    final idx = playerIds.indexOf(playerId);
    if (idx < 0) return '不明';

    final seatLabel = 'プレイヤー${idx + 1}';
    final name = playerNames[playerId];
    final displayName = hideOpponentNames || name == null || name.isEmpty
        ? seatLabel
        : name;

    if (BotLogic.isBot(playerId)) return '$displayName（Bot）';
    if (afkPlayerIds.contains(playerId)) return '$displayName（離脱）';
    if (hostId != null && playerId == hostId) return '$displayName（ホスト）';
    return displayName;
  }

  /// レーティング等のバックエンド用。実名を優先する。
  static String resolveForRating({
    required String playerId,
    required List<String> playerIds,
    required Map<String, String> playerNames,
  }) {
    if (BotLogic.isBot(playerId)) return BotLogic.botDisplayName(playerId);
    final name = playerNames[playerId];
    if (name != null && name.isNotEmpty) return name;
    final idx = playerIds.indexOf(playerId);
    return idx >= 0 ? 'プレイヤー${idx + 1}' : playerId;
  }

  /// ランキング一覧用。自分以外は設定に応じて匿名化する。
  static String resolveForRanking({
    required RankingEntry entry,
    required String? myId,
    bool hideOpponentNames = false,
  }) {
    if (hideOpponentNames && (myId == null || entry.id != myId)) {
      return '---';
    }
    return normalizeStoredPlayerName(id: entry.id, rawName: entry.playerName);
  }

  /// モリーランキング一覧用
  static String resolveForMorrieRanking({
    required String playerName,
    required String id,
    required String? myId,
    bool hideOpponentNames = false,
  }) {
    if (hideOpponentNames && (myId == null || id != myId)) {
      return '---';
    }
    return normalizeStoredPlayerName(id: id, rawName: playerName);
  }
}
