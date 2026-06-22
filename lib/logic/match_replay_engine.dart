import '../features/game/game_board_view.dart';
import '../logic/bot_logic.dart';
import '../logic/match_record_codec.dart';
import '../models/match_event.dart';
import '../models/match_record.dart';

/// リプレイ1フレーム分の盤面状態
class ReplayFrame {
  final int index;
  final String description;
  final Map<String, List<CardWidget>> hands;
  final int fieldNumber;
  final Suit fieldSuit;
  final List<CardWidget> fieldHistory;
  final int deckCount;
  final String? lastPlayerId;
  final int? turnIndex;
  final bool isInitialPhase;
  final MatchEventType? eventType;

  const ReplayFrame({
    required this.index,
    required this.description,
    required this.hands,
    required this.fieldNumber,
    required this.fieldSuit,
    required this.fieldHistory,
    required this.deckCount,
    this.lastPlayerId,
    this.turnIndex,
    this.isInitialPhase = false,
    this.eventType,
  });

  /// 手番プレイヤー ID（範囲外の turnIndex は null）
  String? turnPlayerId(List<String> playerIds) {
    final idx = turnIndex;
    if (idx == null || idx < 0 || idx >= playerIds.length) return null;
    return playerIds[idx];
  }
}

class MatchReplayEngine {
  static int? normalizeTurnIndex(dynamic raw, int playerCount) {
    if (raw is! num || playerCount <= 0) return null;
    final idx = raw.round();
    if (idx < 0 || idx >= playerCount) return null;
    return idx;
  }

  static List<ReplayFrame> buildFrames(MatchRecord record) {
    try {
      return _buildFramesUnsafe(record);
    } catch (e) {
      throw StateError('試合記録の解析に失敗しました: $e');
    }
  }

  static List<ReplayFrame> _buildFramesUnsafe(MatchRecord record) {
    final meta = record.meta;
    final frames = <ReplayFrame>[];

    var hands = _parseHands(record.initial['hands']);
    var fieldNumber = _fieldNumber(record.initial['field']);
    var fieldSuit = _fieldSuit(record.initial['field']);
    var fieldHistory = _parseHistory(record.initial['fieldHistory']);
    var deckCount = _deckLength(record.initial['deck']);
    var lastPlayerId = record.initial['lastPlayerId']?.toString();
    var turnIndex = normalizeTurnIndex(
      record.initial['currentTurnIndex'],
      meta.playerIds.length,
    );
    var isInitialPhase = record.initial['isInitialPhase'] == true;

    frames.add(
      ReplayFrame(
        index: 0,
        description: '試合開始',
        hands: _copyHands(hands),
        fieldNumber: fieldNumber,
        fieldSuit: fieldSuit,
        fieldHistory: List<CardWidget>.from(fieldHistory),
        deckCount: deckCount,
        lastPlayerId: lastPlayerId,
        turnIndex: turnIndex,
        isInitialPhase: isInitialPhase,
      ),
    );

    var frameIndex = 1;
    for (final event in record.events) {
      if (event.type == MatchEventType.matchStart) continue;

      if (event.payload['hands'] is Map) {
        hands = _parseHands(event.payload['hands']);
      }

      final payloadField = event.payload['field'];
      if (payloadField is Map) {
        fieldNumber = _fieldNumber(payloadField);
        fieldSuit = _fieldSuit(payloadField);
      }

      switch (event.type) {
        case MatchEventType.fieldFlip:
          final card = _parseSingleCard(event.payload['card']);
          if (card != null) {
            fieldHistory = [...fieldHistory, card];
            lastPlayerId = 'system';
            isInitialPhase = true;
            deckCount = (deckCount - 1).clamp(0, 999);
          }
        case MatchEventType.playCard:
          final card = _parseSingleCard(event.payload['card']);
          if (card != null) {
            fieldHistory = [...fieldHistory, card];
            lastPlayerId = event.actorId;
            if (event.payload.containsKey('isInitialPhase')) {
              isInitialPhase = event.payload['isInitialPhase'] == true;
            }
          }
        case MatchEventType.draw:
          lastPlayerId = event.actorId;
          if (event.payload['deckReset'] == true) {
            final resetDeck = event.payload['deck'];
            if (resetDeck is List) deckCount = resetDeck.length;
          } else {
            deckCount = (deckCount - 1).clamp(0, 999);
          }
        case MatchEventType.deckReset:
          final resetDeck = event.payload['deck'];
          if (resetDeck is List) deckCount = resetDeck.length;
          final resetField = event.payload['field'];
          if (resetField is Map) {
            fieldNumber = _fieldNumber(resetField);
            fieldSuit = _fieldSuit(resetField);
            fieldHistory = [CardWidget(number: fieldNumber, suit: fieldSuit)];
          }
        case MatchEventType.mori:
        case MatchEventType.moriGaeshi:
          lastPlayerId = event.actorId;
        case MatchEventType.openJoker:
          lastPlayerId = event.actorId;
        case MatchEventType.matchEnd:
          break;
        case MatchEventType.matchStart:
          break;
      }

      if (event.payload.containsKey('turnIndex')) {
        turnIndex = normalizeTurnIndex(event.payload['turnIndex'], meta.playerIds.length);
      }

      frames.add(
        ReplayFrame(
          index: frameIndex++,
          description: _describeEvent(event, meta),
          hands: _copyHands(hands),
          fieldNumber: fieldNumber,
          fieldSuit: fieldSuit,
          fieldHistory: List<CardWidget>.from(fieldHistory),
          deckCount: deckCount,
          lastPlayerId: lastPlayerId,
          turnIndex: turnIndex,
          isInitialPhase: isInitialPhase,
          eventType: event.type,
        ),
      );
    }

    return frames;
  }

  static String playerLabel(String? playerId, MatchRecordMeta meta) {
    if (playerId == null || playerId.isEmpty) return '不明';
    if (playerId == 'system') return '山札';
    final name = meta.playerNames[playerId];
    if (BotLogic.isBot(playerId)) {
      return name != null && name.isNotEmpty ? '$name（Bot）' : BotLogic.botDisplayName(playerId);
    }
    if (name != null && name.isNotEmpty) return name;
    final idx = meta.playerIds.indexOf(playerId);
    return idx >= 0 ? 'プレイヤー${idx + 1}' : playerId;
  }

  static String resultLabel(MatchRecordResult? result, MatchRecordMeta meta) {
    if (result == null) return '結果未記録';
    switch (result.endReason) {
      case 'mori':
        final winner = playerLabel(result.winnerId, meta);
        final loser = playerLabel(result.loserId, meta);
        return 'もり: $winner の勝利（$loser が敗北）';
      case 'burst':
        return 'バースト: ${playerLabel(result.loserId, meta)} の敗北';
      default:
        return '試合終了';
    }
  }

  static Map<String, List<CardWidget>> _copyHands(Map<String, List<CardWidget>> hands) =>
      hands.map((k, v) => MapEntry(k, List<CardWidget>.from(v)));

  static Map<String, List<CardWidget>> _parseHands(dynamic raw) {
    if (raw is! Map) return {};
    final result = <String, List<CardWidget>>{};
    raw.forEach((key, value) {
      if (value is List) {
        result[key.toString()] = MatchRecordCodec.parseHand(value);
      }
    });
    return result;
  }

  static List<CardWidget> _parseHistory(dynamic raw) {
    if (raw is! List) return [];
    return MatchRecordCodec.parseHand(raw);
  }

  static int _deckLength(dynamic raw) => raw is List ? raw.length : 0;

  static int _fieldNumber(dynamic raw) {
    if (raw is Map && raw['number'] is num) return (raw['number'] as num).round();
    return -1;
  }

  static Suit _fieldSuit(dynamic raw) {
    if (raw is Map && raw['suit'] is String) {
      return Suit.values.firstWhere((e) => e.name == raw['suit'], orElse: () => Suit.joker);
    }
    return Suit.joker;
  }

  static CardWidget? _parseSingleCard(dynamic raw) {
    if (raw is! Map) return null;
    return MatchRecordCodec.parseCard(Map<dynamic, dynamic>.from(raw));
  }

  static String _describeEvent(MatchEvent event, MatchRecordMeta meta) {
    final actor = playerLabel(event.actorId, meta);
    final card = _parseSingleCard(event.payload['card']);

    switch (event.type) {
      case MatchEventType.fieldFlip:
        return card != null ? '山札から ${_cardLabel(card)} をめくる' : '山札をめくる';
      case MatchEventType.playCard:
        return card != null ? '$actor が ${_cardLabel(card)} を出す' : '$actor がカードを出す';
      case MatchEventType.draw:
        if (event.payload['burst'] == true) {
          return '$actor がドロー → バースト';
        }
        return card != null ? '$actor が ${_cardLabel(card)} をドロー' : '$actor がドロー';
      case MatchEventType.deckReset:
        return '山札を切り直す';
      case MatchEventType.mori:
        return '$actor がもり宣言';
      case MatchEventType.moriGaeshi:
        return '$actor がもり返し';
      case MatchEventType.openJoker:
        return event.payload['jokerPlusOne'] == true
            ? '$actor がオープンジョーカー（係数3）'
            : '$actor がオープンジョーカー';
      case MatchEventType.matchEnd:
        return resultLabel(MatchRecordResultJson.fromJson(event.payload), meta);
      case MatchEventType.matchStart:
        return '試合開始';
    }
  }

  static String _cardLabel(CardWidget card) {
    if (card.suit == Suit.joker) return 'JOKER';
    const marks = {
      Suit.spade: '♠',
      Suit.heart: '♥',
      Suit.diamond: '♦',
      Suit.club: '♣',
    };
    var num = '${card.number}';
    if (card.number == 11) num = 'J';
    if (card.number == 12) num = 'Q';
    if (card.number == 13) num = 'K';
    if (card.number == 1) num = 'A';
    return '$num${marks[card.suit]}';
  }
}
