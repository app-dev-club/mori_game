import 'dart:async';

import 'package:flutter/material.dart';

import '../../logic/match_replay_engine.dart';
import '../../models/match_record.dart';
import '../../services/match_record_service.dart';
import '../game/game_board_view.dart';

class MatchReplayPage extends StatefulWidget {
  final String recordId;
  final bool hideOpponentNames;

  const MatchReplayPage({
    super.key,
    required this.recordId,
    this.hideOpponentNames = false,
  });

  @override
  State<MatchReplayPage> createState() => _MatchReplayPageState();
}

class _MatchReplayPageState extends State<MatchReplayPage> {
  final MatchRecordService _recordService = MatchRecordService();

  bool _loading = true;
  String? _error;
  MatchRecord? _record;
  List<ReplayFrame> _frames = const [];
  int _frameIndex = 0;
  String? _povPlayerId;
  bool _playing = false;
  Timer? _playTimer;

  static const _autoPlayInterval = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await _recordService.loadRecord(widget.recordId);
      if (!mounted) return;
      if (record == null) {
        setState(() {
          _loading = false;
          _error = '試合記録が見つかりません';
        });
        return;
      }
      final frames = MatchReplayEngine.buildFrames(record);
      final humanIds = record.meta.playerIds
          .where((id) => id != 'system' && !record.meta.botIds.contains(id));
      final pov = humanIds.isNotEmpty
          ? humanIds.first
          : (record.meta.playerIds.isNotEmpty ? record.meta.playerIds.first : null);
      if (pov == null) {
        setState(() {
          _loading = false;
          _error = '試合記録にプレイヤー情報がありません';
        });
        return;
      }
      setState(() {
        _record = record;
        _frames = frames;
        _frameIndex = 0;
        _povPlayerId = pov;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = formatMatchRecordLoadError(e);
      });
    }
  }

  ReplayFrame? get _frame =>
      _frames.isEmpty || _frameIndex < 0 || _frameIndex >= _frames.length ? null : _frames[_frameIndex];

  void _setFrame(int index) {
    if (_frames.isEmpty) return;
    final clamped = index.clamp(0, _frames.length - 1);
    setState(() => _frameIndex = clamped);
    if (clamped >= _frames.length - 1) _stopPlay();
  }

  void _stepBack() => _setFrame(_frameIndex - 1);
  void _stepForward() => _setFrame(_frameIndex + 1);

  void _togglePlay() {
    if (_playing) {
      _stopPlay();
    } else {
      _startPlay();
    }
  }

  void _startPlay() {
    if (_frames.isEmpty || _frameIndex >= _frames.length - 1) {
      if (_frameIndex >= _frames.length - 1) _setFrame(0);
    }
    setState(() => _playing = true);
    _playTimer?.cancel();
    _playTimer = Timer.periodic(_autoPlayInterval, (_) {
      if (!mounted) return;
      if (_frameIndex >= _frames.length - 1) {
        _stopPlay();
        return;
      }
      _setFrame(_frameIndex + 1);
    });
  }

  void _stopPlay() {
    _playTimer?.cancel();
    _playTimer = null;
    if (mounted) setState(() => _playing = false);
  }

  String _playerLabel(String id) {
    final meta = _record!.meta;
    if (widget.hideOpponentNames && id != _povPlayerId) {
      final idx = meta.playerIds.indexOf(id);
      return idx >= 0 ? 'プレイヤー${idx + 1}' : id;
    }
    return MatchReplayEngine.playerLabel(id, meta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: Text(
          _record != null
              ? 'リプレイ ${ _record!.meta.roomId } (${_record!.meta.matchIndex}/${_record!.meta.seriesTotal})'
              : 'リプレイ',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.orangeAccent))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _load, child: const Text('再試行')),
                      ],
                    ),
                  ),
                )
              : Column(
                  children: [
                    _buildEventBanner(),
                    Expanded(child: _buildBoard()),
                    _buildControls(),
                  ],
                ),
    );
  }

  Widget _buildEventBanner() {
    final frame = _frame;
    final meta = _record!.meta;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.black38,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            frame?.description ?? '',
            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
          ),
          if (frame != null) ...[
            const SizedBox(height: 4),
            Builder(
              builder: (context) {
                final turnPlayer = frame.turnPlayerId(meta.playerIds);
                return Text(
                  '手番: ${turnPlayer != null ? _playerLabel(turnPlayer) : '—'}'
                  ' · 山札 ${frame.deckCount}枚'
                  '${frame.isInitialPhase ? ' · 初手フェーズ' : ''}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBoard() {
    final frame = _frame;
    final meta = _record!.meta;
    if (frame == null) return const SizedBox.shrink();

    final povId = _povPlayerId != null && meta.playerIds.contains(_povPlayerId)
        ? _povPlayerId!
        : (meta.playerIds.isNotEmpty ? meta.playerIds.first : null);
    if (povId == null) {
      return const Center(
        child: Text('プレイヤー情報がありません', style: TextStyle(color: Colors.white70)),
      );
    }
    final opponents = meta.playerIds.where((id) => id != povId).toList();
    final povHand = frame.hands[povId] ?? const <CardWidget>[];

    return LayoutBuilder(
      builder: (context, constraints) {
        final boardWidth = constraints.maxWidth;
        final layout = HandCardLayout.compute(
          boardWidth * 0.92,
          povHand.length.clamp(1, 7),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 16),
            child: Column(
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: opponents.map((id) => _buildOpponentPanel(id, frame)).toList(),
                ),
                const SizedBox(height: 24),
                _buildField(frame),
                const SizedBox(height: 24),
                if (meta.playerIds.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DropdownButton<String>(
                      value: meta.playerIds.contains(povId) ? povId : null,
                      hint: const Text('視点を選択', style: TextStyle(color: Colors.white70)),
                      dropdownColor: const Color(0xFF2E7D32),
                      style: const TextStyle(color: Colors.white),
                      underline: Container(height: 1, color: Colors.white38),
                      items: meta.playerIds
                          .map(
                            (id) => DropdownMenuItem(
                              value: id,
                              child: Text('視点: ${_playerLabel(id)}'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _povPlayerId = v);
                      },
                    ),
                  ),
                SizedBox(
                  height: layout.height + 28,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.bottomCenter,
                    children: [
                      for (var i = 0; i < povHand.length; i++)
                        Positioned(
                          left: (boardWidth - layout.totalWidth(povHand.length)) / 2 + i * layout.step,
                          bottom: 0,
                          child: CardWidget(
                            number: povHand[i].number,
                            suit: povHand[i].suit,
                            width: layout.width,
                            height: layout.height,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${_playerLabel(povId)} の手札 (${povHand.length}枚)',
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOpponentPanel(String playerId, ReplayFrame frame) {
    final hand = frame.hands[playerId] ?? const <CardWidget>[];
    final meta = _record!.meta;
    final isActive = frame.turnPlayerId(meta.playerIds) == playerId;
    final isLastActor = frame.lastPlayerId == playerId;

    return Container(
      width: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isActive ? Colors.orange.withValues(alpha: 0.25) : Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLastActor ? Colors.amberAccent : Colors.white24,
          width: isLastActor ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            _playerLabel(playerId),
            style: TextStyle(
              color: isActive ? Colors.orangeAccent : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
          OpponentHandVisual(
            count: hand.length.clamp(0, 52),
            cardWidth: 36,
            cardHeight: 54,
          ),
          Text(
            '${hand.length}枚',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildField(ReplayFrame frame) {
    if (frame.fieldNumber < 0 || (frame.fieldSuit == Suit.joker && frame.fieldHistory.isEmpty)) {
      return const Text('場: —', style: TextStyle(color: Colors.white54));
    }

    return Column(
      children: [
        const Text('場', style: TextStyle(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 8),
        CardWidget(
          number: frame.fieldNumber,
          suit: frame.fieldSuit,
          width: 72,
          height: 108,
        ),
        if (frame.fieldHistory.length > 1) ...[
          const SizedBox(height: 8),
          Text(
            '履歴 ${frame.fieldHistory.length}枚',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ],
    );
  }

  Widget _buildControls() {
    final atEnd = _frames.isNotEmpty && _frameIndex >= _frames.length - 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.black38,
        border: Border(top: BorderSide(color: Colors.white24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_frames.length > 1)
            Slider(
              value: _frameIndex.toDouble(),
              min: 0,
              max: (_frames.length - 1).toDouble(),
              divisions: _frames.length - 1,
              activeColor: Colors.orangeAccent,
              inactiveColor: Colors.white24,
              label: '${_frameIndex + 1}/${_frames.length}',
              onChanged: (v) {
                _stopPlay();
                _setFrame(v.round());
              },
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: 32,
                color: Colors.white,
                onPressed: _frameIndex > 0 ? () { _stopPlay(); _stepBack(); } : null,
                icon: const Icon(Icons.skip_previous),
                tooltip: '前へ',
              ),
              IconButton(
                iconSize: 44,
                color: Colors.orangeAccent,
                onPressed: _frames.isEmpty
                    ? null
                    : () {
                        if (atEnd && !_playing) {
                          _setFrame(0);
                          _startPlay();
                        } else {
                          _togglePlay();
                        }
                      },
                icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_filled),
                tooltip: _playing ? '一時停止' : '再生',
              ),
              IconButton(
                iconSize: 32,
                color: Colors.white,
                onPressed: _frameIndex < _frames.length - 1
                    ? () {
                        _stopPlay();
                        _stepForward();
                      }
                    : null,
                icon: const Icon(Icons.skip_next),
                tooltip: '次へ',
              ),
            ],
          ),
          Text(
            '${_frameIndex + 1} / ${_frames.length}',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (_record?.result != null) ...[
            const SizedBox(height: 8),
            Text(
              MatchReplayEngine.resultLabel(_record!.result, _record!.meta),
              style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}
