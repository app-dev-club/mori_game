import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

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

void _logMatchRecordError(String action, Object error, [StackTrace? stack]) {
  if (!kDebugMode) return;
  debugPrint('MatchRecordService.$action failed: $error');
  if (stack != null) debugPrint('$stack');
}

/// 試合内容を Firebase Realtime Database に記録（リプレイ・機械学習用）
class MatchRecordService {
  static const _listTimeout = Duration(seconds: 20);
  static const _loadTimeout = Duration(seconds: 45);

  DatabaseReference get _root => FirebaseDatabase.instance.ref('matchRecords');
  DatabaseReference get _summariesRoot =>
      FirebaseDatabase.instance.ref('matchRecordSummaries');

  String? _activeRecordId;
  MatchRecordMeta? _activeMeta;
  int _eventSeq = 0;
  bool _finalized = false;
  Future<void>? _startInFlight;

  bool get isRecording => _activeRecordId != null && !_finalized;

  String? get activeRecordId => _activeRecordId;

  /// 新しい試合の記録を開始（ルーム×試合番号で1件に統一）
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
    final inFlight = _startInFlight;
    if (inFlight != null) {
      await inFlight;
      if (_isRecordingMatch(roomId: roomId, matchIndex: matchIndex)) return;
    }

    final startFuture = _startMatchLocked(
      roomId: roomId,
      matchIndex: matchIndex,
      seriesTotal: seriesTotal,
      turnTimeoutSeconds: turnTimeoutSeconds,
      playerIds: playerIds,
      playerNames: playerNames,
      botIds: botIds,
      hands: hands,
      deck: deck,
      field: field,
      fieldHistory: fieldHistory,
      currentTurnIndex: currentTurnIndex,
      isInitialPhase: isInitialPhase,
    );
    _startInFlight = startFuture;
    try {
      await startFuture;
    } finally {
      if (identical(_startInFlight, startFuture)) {
        _startInFlight = null;
      }
    }
  }

  Future<void> _startMatchLocked({
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
    if (_isRecordingMatch(roomId: roomId, matchIndex: matchIndex)) return;

    if (isRecording) {
      reset();
    }

    final openRecordId = await _findOpenRecordId(
      roomId: roomId,
      matchIndex: matchIndex,
    );
    if (openRecordId != null) {
      final adopted = await _adoptRecord(openRecordId);
      if (adopted) return;
    }

    final startedAtMs = DateTime.now().millisecondsSinceEpoch;
    final recordId = MatchRecordCodec.buildRecordId(
      roomId: roomId,
      matchIndex: matchIndex,
      startedAtMs: startedAtMs,
    );

    final existingSnap = await _root.child(recordId).get();
    if (existingSnap.child('result').value != null) {
      return;
    }

    if (existingSnap.exists) {
      await _adoptRecord(recordId);
      return;
    }

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

    _activeRecordId = recordId;
    _activeMeta = meta;
    _eventSeq = 0;
    _finalized = false;

    try {
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

      await _upsertSummary(meta: meta, result: null);

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
    } catch (e, st) {
      reset();
      _logMatchRecordError('startMatch', e, st);
      rethrow;
    }
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

    try {
      await _append(
        MatchEvent(
          seq: _nextSeq(),
          type: type,
          atMs: DateTime.now().millisecondsSinceEpoch,
          actorId: actorId,
          payload: eventPayload,
        ),
      );
    } catch (e, st) {
      _logMatchRecordError('recordEvent', e, st);
    }
  }

  /// 試合終了時に結果を書き込み、記録を確定
  Future<void> finalizeMatch(MatchRecordResult result) async {
    if (_activeRecordId == null || _finalized) return;

    final recordId = _activeRecordId!;
    final meta = _activeMeta;

    try {
      await recordEvent(
        type: MatchEventType.matchEnd,
        payload: result.toJson(),
      );

      await _root.child('$recordId/result').set(result.toJson());
      if (meta != null) {
        await _upsertSummary(meta: meta, result: result);
      } else {
        await _summariesRoot.child('$recordId/result').set(result.toJson());
      }
    } catch (e, st) {
      _logMatchRecordError('finalizeMatch', e, st);
      rethrow;
    } finally {
      _finalized = true;
      _activeRecordId = null;
      _activeMeta = null;
      _eventSeq = 0;
    }
  }

  void reset() {
    _activeRecordId = null;
    _activeMeta = null;
    _eventSeq = 0;
    _finalized = false;
  }

  /// 既存の未確定記録をローカルに引き継ぐ（精算担当が別クライアントのとき）
  Future<bool> tryAdoptExisting({
    required String roomId,
    required int matchIndex,
  }) async {
    if (isRecording) return true;

    final recordId = await _findOpenRecordId(
      roomId: roomId,
      matchIndex: matchIndex,
    );
    if (recordId == null) return false;

    return _adoptRecord(recordId);
  }

  bool _isRecordingMatch({required String roomId, required int matchIndex}) {
    if (!isRecording) return false;
    final meta = _activeMeta;
    return meta != null &&
        meta.roomId == roomId &&
        meta.matchIndex == matchIndex;
  }

  Future<bool> _adoptRecord(String recordId) async {
    final existingSnap = await _root.child(recordId).get();
    if (!existingSnap.exists || existingSnap.child('result').value != null) {
      return false;
    }

    final data = Map<dynamic, dynamic>.from(existingSnap.value as Map);
    final metaRaw = data['meta'];
    if (metaRaw is! Map) return false;

    final metaMap = Map<dynamic, dynamic>.from(metaRaw);
    if (metaMap['recordId'] == null || metaMap['recordId'].toString().isEmpty) {
      metaMap['recordId'] = recordId;
    }
    _activeRecordId = recordId;
    _activeMeta = MatchRecordMetaJson.fromJson(metaMap);
    _eventSeq = _maxEventSeq(data['events']);
    _finalized = false;
    return true;
  }

  Future<String?> _findOpenRecordId({
    required String roomId,
    required int matchIndex,
  }) async {
    final snap = await _root.get();
    if (!snap.exists || snap.value is! Map) return null;

    String? bestId;
    var bestStartedAt = -1;
    final raw = Map<dynamic, dynamic>.from(snap.value as Map);
    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final recordId = entry.key.toString();
      final data = Map<dynamic, dynamic>.from(entry.value as Map);
      if (data['result'] != null) continue;
      final metaRaw = data['meta'];
      if (metaRaw is! Map) continue;
      final meta = Map<dynamic, dynamic>.from(metaRaw);
      if (meta['roomId']?.toString() != roomId) continue;
      if (MatchRecordCodec.readInt(meta['matchIndex'], fallback: -1) !=
          matchIndex) {
        continue;
      }
      final startedAt = MatchRecordCodec.readInt(
        meta['startedAt'],
        fallback: 0,
      );
      if (startedAt > bestStartedAt) {
        bestStartedAt = startedAt;
        bestId = recordId;
      }
    }
    return bestId;
  }

  int _nextSeq() => ++_eventSeq;

  Future<void> _append(MatchEvent event) async {
    final recordId = _activeRecordId;
    if (recordId == null) return;
    await _root.child('$recordId/events').push().set(event.toJson());
  }

  Future<void> _upsertSummary({
    required MatchRecordMeta meta,
    MatchRecordResult? result,
  }) async {
    try {
      await _summariesRoot.child(meta.recordId).set({
        'meta': meta.toJson(),
        'result': result?.toJson(),
      });
    } catch (e, st) {
      _logMatchRecordError('_upsertSummary', e, st);
    }
  }

  /// 保存済み試合の一覧（新しい順）。軽量インデックス + 未索引の記録を補完。
  Future<List<MatchRecordSummary>> listRecentRecords({int limit = 50}) async {
    List<MatchRecordSummary> summaries;
    try {
      final snap = await _summariesRoot.get().timeout(_listTimeout);
      summaries = _loadSummaries(snap, limit: 9999);
    } on FirebaseException catch (e) {
      if (e.code != 'permission-denied') rethrow;
      summaries = await _backfillSummariesFromFullRecords(
        limit: limit,
        writeIndex: false,
      );
      return summaries;
    }

    final indexedIds = summaries.map((s) => s.meta.recordId).toSet();
    final merged = await _mergeMissingSummaries(summaries, indexedIds);
    final deduped = _dedupeSummaries(merged);
    deduped.sort((a, b) => b.meta.startedAtMs.compareTo(a.meta.startedAtMs));
    if (deduped.length <= limit) return deduped;
    return deduped.sublist(0, limit);
  }

  /// 同一 recordId の重複だけを除外する。再戦で同じ部屋・同じ試合番号に
  /// 戻ることがあるため、roomId + matchIndex では畳まない。
  static List<MatchRecordSummary> _dedupeSummaries(
    List<MatchRecordSummary> summaries,
  ) {
    final best = <String, MatchRecordSummary>{};
    for (final summary in summaries) {
      final key = summary.meta.recordId;
      final existing = best[key];
      if (existing == null) {
        best[key] = summary;
        continue;
      }
      final hasResult = summary.result != null;
      final existingHasResult = existing.result != null;
      if (hasResult && !existingHasResult) {
        best[key] = summary;
      } else if (hasResult == existingHasResult &&
          summary.meta.startedAtMs > existing.meta.startedAtMs) {
        best[key] = summary;
      }
    }
    return best.values.toList();
  }

  static int _maxEventSeq(dynamic eventsRaw) {
    if (eventsRaw is! Map) return 0;
    var maxSeq = 0;
    for (final value in eventsRaw.values) {
      if (value is! Map) continue;
      final seq = value['seq'];
      if (seq is num && seq.round() > maxSeq) {
        maxSeq = seq.round();
      }
    }
    return maxSeq;
  }

  Future<List<MatchRecordSummary>> _mergeMissingSummaries(
    List<MatchRecordSummary> summaries,
    Set<String> indexedIds,
  ) async {
    try {
      final snap = await _root.get().timeout(_loadTimeout);
      if (!snap.exists || snap.value is! Map) return summaries;

      final merged = List<MatchRecordSummary>.from(summaries);
      final raw = Map<dynamic, dynamic>.from(snap.value as Map);
      final updates = <String, dynamic>{};

      for (final entry in raw.entries) {
        if (entry.value is! Map) continue;
        final recordId = entry.key.toString();
        if (indexedIds.contains(recordId)) continue;

        final data = Map<dynamic, dynamic>.from(entry.value as Map);
        final metaRaw = data['meta'];
        if (metaRaw is! Map) continue;

        final metaMap = Map<dynamic, dynamic>.from(metaRaw);
        if (metaMap['recordId'] == null ||
            metaMap['recordId'].toString().isEmpty) {
          metaMap['recordId'] = recordId;
        }

        final meta = MatchRecordMetaJson.fromJson(metaMap);
        final result = MatchRecordResultJson.fromJson(data['result']);
        merged.add(MatchRecordSummary(meta: meta, result: result));
        updates[recordId] = {'meta': meta.toJson(), 'result': result?.toJson()};
      }

      if (updates.isNotEmpty) {
        try {
          await _summariesRoot.update(updates);
        } catch (e, st) {
          _logMatchRecordError('_mergeMissingSummaries', e, st);
        }
      }

      return merged;
    } catch (e, st) {
      _logMatchRecordError('_mergeMissingSummaries', e, st);
      return summaries;
    }
  }

  List<MatchRecordSummary> _loadSummaries(
    DataSnapshot snap, {
    required int limit,
  }) {
    if (!snap.exists || snap.value is! Map) return [];

    final summaries = <MatchRecordSummary>[];
    final raw = Map<dynamic, dynamic>.from(snap.value as Map);

    for (final entry in raw.entries) {
      if (entry.value is! Map) continue;
      final summary = _parseSummaryEntry(
        entry.key.toString(),
        entry.value as Map,
      );
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
      if (metaMap['recordId'] == null ||
          metaMap['recordId'].toString().isEmpty) {
        metaMap['recordId'] = recordId;
      }

      final meta = MatchRecordMetaJson.fromJson(metaMap);
      final result = MatchRecordResultJson.fromJson(data['result']);
      summaries.add(MatchRecordSummary(meta: meta, result: result));
      updates[recordId] = {'meta': meta.toJson(), 'result': result?.toJson()};
    }

    if (writeIndex && updates.isNotEmpty) {
      try {
        await _summariesRoot.update(updates);
      } catch (e, st) {
        _logMatchRecordError('_backfillSummariesFromFullRecords', e, st);
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
        ? Map<String, dynamic>.from(
            initialRaw.map((k, v) => MapEntry(k.toString(), v)),
          )
        : <String, dynamic>{};

    return MatchRecord(
      meta: MatchRecordMetaJson.fromJson(metaMap),
      initial: initial,
      events: parseMatchEvents(data['events']),
      result: MatchRecordResultJson.fromJson(data['result']),
    );
  }
}
