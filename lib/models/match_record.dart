import 'match_event.dart';

/// Firebase から読み込んだ試合記録一式
class MatchRecord {
  final MatchRecordMeta meta;
  final Map<String, dynamic> initial;
  final List<MatchEvent> events;
  final MatchRecordResult? result;

  const MatchRecord({
    required this.meta,
    required this.initial,
    required this.events,
    this.result,
  });
}

/// 一覧表示用（events は未読込）
class MatchRecordSummary {
  final MatchRecordMeta meta;
  final MatchRecordResult? result;

  const MatchRecordSummary({
    required this.meta,
    this.result,
  });
}

extension MatchRecordMetaJson on MatchRecordMeta {
  static MatchRecordMeta fromJson(Map<dynamic, dynamic> json) {
    final namesRaw = json['playerNames'];
    final names = namesRaw is Map
        ? namesRaw.map((k, v) => MapEntry(k.toString(), v.toString()))
        : <String, String>{};

    return MatchRecordMeta(
      schemaVersion: json['schemaVersion'] is num ? (json['schemaVersion'] as num).round() : 1,
      recordId: json['recordId']?.toString() ?? '',
      roomId: json['roomId']?.toString() ?? '',
      matchIndex: json['matchIndex'] is num ? (json['matchIndex'] as num).round() : 1,
      seriesTotal: json['seriesTotal'] is num ? (json['seriesTotal'] as num).round() : 1,
      turnTimeoutSeconds:
          json['turnTimeoutSeconds'] is num ? (json['turnTimeoutSeconds'] as num).round() : 10,
      playerIds: (json['playerIds'] as List? ?? []).map((e) => e.toString()).toList(),
      playerNames: names,
      botIds: (json['botIds'] as List? ?? []).map((e) => e.toString()).toList(),
      startedAtMs: json['startedAt'] is num ? (json['startedAt'] as num).round() : 0,
    );
  }
}

extension MatchRecordResultJson on MatchRecordResult {
  static MatchRecordResult? fromJson(dynamic raw) {
    if (raw is! Map) return null;
    final json = Map<dynamic, dynamic>.from(raw);
    final deltasRaw = json['pointDeltas'];
    final deltas = deltasRaw is Map
        ? deltasRaw.map(
            (k, v) => MapEntry(k.toString(), v is num ? v.round() : 0),
          )
        : <String, int>{};

    return MatchRecordResult(
      endReason: json['endReason']?.toString() ?? 'unknown',
      winnerId: json['winnerId']?.toString(),
      loserId: json['loserId']?.toString(),
      pointDeltas: deltas,
      moriGaeshiCount: json['moriGaeshiCount'] is num ? (json['moriGaeshiCount'] as num).round() : null,
      moriDeclarationFactors: (json['moriDeclarationFactors'] as List? ?? [])
          .map((e) => e is num ? e.round() : 0)
          .toList(),
      endedAtMs: json['endedAt'] is num ? (json['endedAt'] as num).round() : 0,
    );
  }
}

List<MatchEvent> parseMatchEvents(dynamic raw) {
  if (raw is! Map) return [];
  final events = <MatchEvent>[];
  for (final value in raw.values) {
    if (value is Map) {
      events.add(MatchEvent.fromJson(Map<dynamic, dynamic>.from(value)));
    }
  }
  events.sort((a, b) => a.seq.compareTo(b.seq));
  return events;
}
