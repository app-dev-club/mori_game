import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../logic/match_record_codec.dart';
import '../models/match_event.dart';
import '../models/match_record.dart';

/// Firebase Realtime Database 読み取りエラーをユーザー向け文言に変換
String formatMatchRecordLoadError(Object error) {
  final msg = error.toString();
  if (msg.contains('permission-denied') || msg.contains('PERMISSION_DENIED')) {
    return '読み取り権限がありません。\n'
        'Firebase の database.rules をデプロイし、ログイン状態を確認してください。';
  }
  if (error is TimeoutException) {
    return '読み込みがタイムアウトしました。\n通信環境を確認して再試行してください。';
  }
  return msg;
}

/// 試合内容を Firebase Realtime Database に記録（リプレイ・機械学習用）
class MatchRecordService {
  static const _listTimeout = Duration(seconds: 20);
  static const _loadTimeout = Duration(seconds: 45);

  DatabaseReference get _root => FirebaseDatabase.instance.ref('matchRecords');
  DatabaseReference get _summariesRoot =>
      FirebaseDatabase.instance.ref('matchRecordSummaries');

  String? _activeRecordId;
  int _eventSeq = 0;
  bool _finalized = false;

  bool get isRecording => _activeRecordId != null && !_finalized;

  String? get activeRecordId => _activeRecordId;

  /// 新しい試合の記録を開始
  Future<void> startMatch({
    required String roomId,
    required int matchIndex,
    required int seriesTotal,
    required int turnTimeoutSeconds,
    required List<String> playerIds,
    required Map<String, String> playerNames,
    required List<String> botIds,
    required Map<String, List<Map<String, dynamic>>> hands,
    required List<Map<String, dynamic>> deck,
    required Map<String, dynamic> field,
    required List<Map<String, dynamic>> fieldHistory,
    required int currentTurnIndex,
    required bool isInitialPhase,
  }) async {
    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    final recordId = MatchRecordCodec.buildRecordId(
      roomId: roomId,
      matchIndex: matchIndex,
      startedAtMs: startedAtMs,
    );

    _activeRecordId = recordId;
    _eventSeq = 0;
    _finalized = false;

    final meta = MatchRecordMeta(
      recordId: recordId,
      roomId: roomId,
      matchIndex: matchIndex,
      seriesTotal: seriesTotal,
      turnTimeoutSeconds: turnTimeoutSeconds,
      playerIds: List<String>.from(playerIds),
      playerNames: Map<String, String>.from(playerNames),
      botIds: List<String>.from(botIds),
      startedAtMs: startedAtMs,
    );

    await _root.child(recordId).set({
      'meta': meta.toJson(),
      'initial': {
        'hands': hands,
        'deck': deck,
        'field': field,
        'fieldHistory': fieldHistory,
        'currentTurnIndex': currentTurnIndex,
        'isInitialPhase': isInitialPhase,
      },
      'events': {},
      'result': null,
    });

    await _summariesRoot.child(recordId).set({
      'meta': meta.toJson(),
      'result': null,
    });

    await _append(
      MatchEvent(
        seq: _nextSeq(),
        type: MatchEventType.matchStart,
        atMs: startedAtMs,
        payload: {
          'hands': hands,
          'deck': deck,
          'field': field,
          'fieldHistory': fieldHistory,
          'currentTurnIndex': currentTurnIndex,
          'isInitialPhase': isInitialPhase,
        },
      ),
    );
  }

  Future<void> recordEvent({
    required MatchEventType type,
    String? actorId,
    Map<String, dynamic> payload = const {},
    Map<String, List<Map<String, dynamic>>>? handsSnapshot,
    int? turnIndex,
    Map<String, dynamic>? field,
  }) async {
    if (!isRecording) return;

    final eventPayload = <String, dynamic>{...payload};
    if (handsSnapshot != null && handsSnapshot.isNotEmpty) {
      eventPayload['hands'] = handsSnapshot;
    }
    if (turnIndex != null) eventPayload['turnIndex'] = turnIndex;
    if (field != null) eventPayload['field'] = field;

    await _append(
      MatchEvent(
        seq: _nextSeq(),
        type: type,
        atMs: DateTime.now().millisecondsSinceEpoch,
        actorId: actorId,
        payload: eventPayload,
      ),
    );
  }

  /// 試合終了時に結果を書き込み、記録を確定
  Future<void> finalizeMatch(MatchRecordResult result) async {
    if (_activeRecordId == null || _finalized) return;

    final recordId = _activeRecordId!;

    await recordEvent(
      type: MatchEventType.matchEnd,
      payload: result.toJson(),
    );

    await _root.child('$recordId/result').set(result.toJson());
    await _summariesRoot.child('$recordId/result').set(result.toJson());
    _finalized = true;
    _activeRecordId = null;
    _eventSeq = 0;
  }

  void reset() {
    _activeRecordId = null;
    _eventSeq = 0;
    _finalized = false;
  }

  int _nextSeq() => ++_eventSeq;

  Future<void> _append(MatchEvent event) async {
    final recordId = _activeRecordId;
    if (recordId == null) return;
    await _root.child('$recordId/events').push().set(event.toJson());
  }

  /// 保存済み試合の一覧（新しい順）。軽量インデックスのみ読む。
  Future<List<MatchRecordSummary>> listRecentRecords({int limit = 50}) async {
    try {
      final snap = await _summariesRoot.get().timeout(_listTimeout);
      final summaries = _loadSummaries(snap, limit: limit);
      if (summaries.isNotEmpty) return summaries;
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      // summaries 未デプロイ時: フル記録から meta のみ抽出（書き込みなし）
      return _backfillSummariesFromFullRecords(limit: limit, writeIndex: false);
    }

    // インデックス未作成の既存記録を1回だけバックフィル
    return _backfillSummariesFromFullRecords(limit: limit);
  }

  List<MatchRecordSummary> _loadSummaries(DataSnapshot snap, {required int limit}) {
    if (!snap.exists || snap.value is! Map) return [];

    final summaries = <MatchRecordSummary>[];
    final raw = Map<dynamic, dynamic>.from(snap.value as Map);

    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final summary = _parseSummaryEntry(entry.key.toString(), entry.value as Map);
      if (summary != null) summaries.add(summary);
    }

    summaries.sort((a, b) => b.meta.startedAtMs.compareTo(a.meta.startedAtMs));
    if (summaries.length <= limit) return summaries;
    return summaries.sublist(0, limit);
  }

  MatchRecordSummary? _parseSummaryEntry(String key, Map rawMap) {
    final data = Map<dynamic, dynamic>.from(rawMap);
    final metaRaw = data['meta'];
    if (metaRaw is! Map) return null;

    final metaMap = Map<dynamic, dynamic>.from(metaRaw);
    if (metaMap['recordId'] == null || metaMap['recordId'].toString().isEmpty) {
      metaMap['recordId'] = key;
    }

    return MatchRecordSummary(
      meta: MatchRecordMetaJson.fromJson(metaMap),
      result: MatchRecordResultJson.fromJson(data['result']),
    );
  }

  /// 既存のフル記録から meta/result だけ抽出してインデックスを作る
  Future<List<MatchRecordSummary>> _backfillSummariesFromFullRecords({
    required int limit,
    bool writeIndex = true,
  }) async {
    final snap = await _root.get().timeout(_loadTimeout);
    if (!snap.exists || snap.value is! Map) return [];

    final summaries = <MatchRecordSummary>[];
    final raw = Map<dynamic, dynamic>.from(snap.value as Map);
    final updates = <String, dynamic>{};

    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final recordId = entry.key.toString();
      final data = Map<dynamic, dynamic>.from(entry.value as Map);
      final metaRaw = data['meta'];
      if (metaRaw is! Map) continue;

      final metaMap = Map<dynamic, dynamic>.from(metaRaw);
      if (metaMap['recordId'] == null || metaMap['recordId'].toString().isEmpty) {
        metaMap['recordId'] = recordId;
      }

      final result = MatchRecordResultJson.fromJson(data['result']);
      summaries.add(
        MatchRecordSummary(
          meta: MatchRecordMetaJson.fromJson(metaMap),
          result: result,
        ),
      );
      updates[recordId] = {
        'meta': metaMap,
        'result': result?.toJson(),
      };
    }

    if (writeIndex && updates.isNotEmpty) {
      try {
        await _summariesRoot.update(updates);
      } on FirebaseException catch (e) {
        if (e.code != 'permission-denied') rethrow;
      }
    }

    summaries.sort((a, b) => b.meta.startedAtMs.compareTo(a.meta.startedAtMs));
    if (summaries.length <= limit) return summaries;
    return summaries.sublist(0, limit);
  }

  /// 試合記録をフル読込（リプレイ用）
  Future<MatchRecord?> loadRecord(String recordId) async {
    final snap = await _root.child(recordId).get().timeout(_loadTimeout);
    if (!snap.exists || snap.value is! Map) return null;

    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    final metaRaw = data['meta'];
    if (metaRaw is! Map) return null;

    final metaMap = Map<dynamic, dynamic>.from(metaRaw);
    if (metaMap['recordId'] == null || metaMap['recordId'].toString().isEmpty) {
      metaMap['recordId'] = recordId;
    }

    final initialRaw = data['initial'];
    final initial = initialRaw is Map
        ? Map<String, dynamic>.from(initialRaw.map((k, v) => MapEntry(k.toString(), v)))
        : <String, dynamic>{};

    return MatchRecord(
      meta: MatchRecordMetaJson.fromJson(metaMap),
      initial: initial,
      events: parseMatchEvents(data['events']),
      result: MatchRecordResultJson.fromJson(data['result']),
    );
  }
}
