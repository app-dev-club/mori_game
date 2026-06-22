/// 試合記録のイベント種別（リプレイ・機械学習用）
enum MatchEventType {
  matchStart('match_start'),
  fieldFlip('field_flip'),
  playCard('play_card'),
  draw('draw'),
  deckReset('deck_reset'),
  mori('mori'),
  moriGaeshi('mori_gaeshi'),
  openJoker('open_joker'),
  matchEnd('match_end');

  const MatchEventType(this.value);
  final String value;

  static MatchEventType? fromValue(String? raw) {
    if (raw == null) return null;
    for (final type in MatchEventType.values) {
      if (type.value == raw) return type;
    }
    return null;
  }
}

/// Firebase に保存する1イベント
class MatchEvent {
  final int seq;
  final MatchEventType type;
  final int atMs;
  final String? actorId;
  final Map<String, dynamic> payload;

  const MatchEvent({
    required this.seq,
    required this.type,
    required this.atMs,
    this.actorId,
    this.payload = const {},
  });

  Map<String, dynamic> toJson() => {
        'seq': seq,
        'type': type.value,
        'at': atMs,
        if (actorId != null) 'actorId': actorId,
        if (payload.isNotEmpty) 'payload': payload,
      };

  factory MatchEvent.fromJson(Map<dynamic, dynamic> json) {
    return MatchEvent(
      seq: json['seq'] is num ? (json['seq'] as num).round() : 0,
      type: MatchEventType.fromValue(json['type']?.toString()) ?? MatchEventType.matchStart,
      atMs: json['at'] is num ? (json['at'] as num).round() : 0,
      actorId: json['actorId']?.toString(),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
    );
  }
}

/// 試合メタ情報
class MatchRecordMeta {
  final int schemaVersion;
  final String recordId;
  final String roomId;
  final int matchIndex;
  final int seriesTotal;
  final int turnTimeoutSeconds;
  final List<String> playerIds;
  final Map<String, String> playerNames;
  final List<String> botIds;
  final int startedAtMs;

  const MatchRecordMeta({
    this.schemaVersion = 1,
    required this.recordId,
    required this.roomId,
    required this.matchIndex,
    required this.seriesTotal,
    required this.turnTimeoutSeconds,
    required this.playerIds,
    required this.playerNames,
    required this.botIds,
    required this.startedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'recordId': recordId,
        'roomId': roomId,
        'matchIndex': matchIndex,
        'seriesTotal': seriesTotal,
        'turnTimeoutSeconds': turnTimeoutSeconds,
        'playerIds': playerIds,
        'playerNames': playerNames,
        'botIds': botIds,
        'startedAt': startedAtMs,
      };
}

/// 試合結果
class MatchRecordResult {
  final String endReason;
  final String? winnerId;
  final String? loserId;
  final Map<String, int> pointDeltas;
  final int? moriGaeshiCount;
  final List<int> moriDeclarationFactors;
  final int endedAtMs;

  const MatchRecordResult({
    required this.endReason,
    this.winnerId,
    this.loserId,
    this.pointDeltas = const {},
    this.moriGaeshiCount,
    this.moriDeclarationFactors = const [],
    required this.endedAtMs,
  });

  Map<String, dynamic> toJson() => {
        'endReason': endReason,
        if (winnerId != null) 'winnerId': winnerId,
        if (loserId != null) 'loserId': loserId,
        'pointDeltas': pointDeltas,
        if (moriGaeshiCount != null) 'moriGaeshiCount': moriGaeshiCount,
        if (moriDeclarationFactors.isNotEmpty)
          'moriDeclarationFactors': moriDeclarationFactors,
        'endedAt': endedAtMs,
      };
}
