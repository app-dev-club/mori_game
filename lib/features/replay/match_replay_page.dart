import 'dart:async';

import 'package:flutter/material.dart';

import '../../logic/match_replay_engine.dart';
import '../../models/match_record.dart';
import '../../services/match_record_service.dart';
import '../game/game_board_view.dart';
import '../game/play_arrow_overlay.dart';
import 'replay_circle_layout.dart';

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
  final GlobalKey _boardStackKey = GlobalKey();
  final GlobalKey _fieldKey = GlobalKey();
  final Map<String, GlobalKey> _playerPanelKeys = {};

  bool _loading = true;
  String? _error;
  MatchRecord? _record;
  List<ReplayFrame> _frames = const [];
  int _frameIndex = 0;
  bool _playing = false;
  Timer? _playTimer;

  Offset? _arrowFrom;
  Offset? _arrowTo;
  String? _arrowLabel;

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

  void _syncPlayerPanelKeys(List<String> playerIds) {
    for (final id in playerIds) {
      _playerPanelKeys.putIfAbsent(id, GlobalKey.new);
    }
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
      if (record.meta.playerIds.isEmpty) {
        setState(() {
          _loading = false;
          _error = '試合記録にプレイヤー情報がありません';
        });
        return;
      }
      final frames = MatchReplayEngine.buildFrames(record);
      _syncPlayerPanelKeys(record.meta.playerIds);
      setState(() {
        _record = record;
        _frames = frames;
        _frameIndex = 0;
        _loading = false;
      });
      _scheduleArrowMeasure();
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
    _scheduleArrowMeasure();
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

  void _scheduleArrowMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureArrow());
  }

  void _measureArrow() {
    if (!mounted) return;
    final frame = _frame;
    final lastId = frame?.lastPlayerId;
    final showArrow = frame != null &&
        frame.fieldNumber >= 0 &&
        lastId != null &&
        lastId != 'system' &&
        _record!.meta.playerIds.contains(lastId);

    if (!showArrow) {
      if (_arrowFrom != null || _arrowTo != null) {
        setState(() {
          _arrowFrom = null;
          _arrowTo = null;
          _arrowLabel = null;
        });
      }
      return;
    }

    final stackBox = _boardStackKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final playerBox =
        _playerPanelKeys[lastId]?.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || fieldBox == null || playerBox == null) return;

    final endpoints =
        PlayArrowGeometry.measureBetween(stackBox, playerBox, fieldBox);
    if (endpoints.from == null || endpoints.to == null) return;

    final label = _playerLabel(lastId);

    if (_offsetNear(endpoints.from!, _arrowFrom) &&
        _offsetNear(endpoints.to!, _arrowTo) &&
        label == _arrowLabel) {
      return;
    }

    setState(() {
      _arrowFrom = endpoints.from;
      _arrowTo = endpoints.to;
      _arrowLabel = label;
    });
  }

  bool _offsetNear(Offset a, Offset? b) {
    if (b == null) return false;
    return (a - b).distance < 2;
  }

  String _playerLabel(String id) {
    final meta = _record!.meta;
    if (widget.hideOpponentNames) {
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
              ? '試合ログ ${_record!.meta.roomId} (${_record!.meta.matchIndex}/${_record!.meta.seriesTotal})'
              : '試合ログ',
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

    final playerIds = meta.playerIds;

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = ReplayCircleLayout.computeForReplay(
          area: area,
          playerIds: playerIds,
          hands: frame.hands,
        );
        _scheduleArrowMeasure();

        return Stack(
          key: _boardStackKey,
          clipBehavior: Clip.hardEdge,
          children: [
            for (var i = 0; i < playerIds.length; i++)
              _buildPositionedPlayerPanel(
                playerId: playerIds[i],
                frame: frame,
                center: layout.playerCenters[i],
                handMaxWidth: layout.handMaxWidth,
                compact: layout.handMaxWidth < 108,
              ),
            Positioned(
              left: layout.fieldCenter.dx - layout.layoutFieldCardWidth / 2,
              top: layout.fieldCenter.dy - layout.layoutFieldCardHeight / 2,
              child: KeyedSubtree(
                key: _fieldKey,
                child: _buildFieldCard(frame, layout),
              ),
            ),
            if (_arrowFrom != null && _arrowTo != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: PlayArrowPainter(
                      from: _arrowFrom!,
                      to: _arrowTo!,
                      label: _arrowLabel ?? '',
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPositionedPlayerPanel({
    required String playerId,
    required ReplayFrame frame,
    required Offset center,
    required double handMaxWidth,
    bool compact = false,
  }) {
    final hand = frame.hands[playerId] ?? const <CardWidget>[];
    final panelSize = ReplayCircleLayout.replayPanelSize(
      hand,
      handMaxWidth,
      compact: compact,
    );

    return Positioned(
      left: center.dx - panelSize.width / 2,
      top: center.dy - panelSize.height / 2,
      width: panelSize.width,
      child: KeyedSubtree(
        key: _playerPanelKeys[playerId],
        child: _buildPlayerHandPanel(
          playerId: playerId,
          frame: frame,
          handMaxWidth: handMaxWidth,
          compact: compact,
        ),
      ),
    );
  }

  Widget _buildFaceUpHand({
    required List<CardWidget> hand,
    required double maxWidth,
    bool compact = false,
  }) {
    if (hand.isEmpty) {
      return const SizedBox(
        height: 24,
        child: Center(
          child: Text('手札なし', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      );
    }

    final cardLayout = compact || maxWidth < 108
        ? HandCardLayout.computeSpectator(
            maxWidth,
            hand.length.clamp(1, 7),
            gap: 4,
          )
        : HandCardLayout.compute(
            maxWidth,
            hand.length.clamp(1, 7),
          );
    final rowWidth = cardLayout.totalWidth(hand.length);

    return SizedBox(
      width: rowWidth,
      height: cardLayout.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        alignment: Alignment.bottomCenter,
        children: [
          for (var i = 0; i < hand.length; i++)
            Positioned(
              left: i * cardLayout.step,
              bottom: 0,
              child: CardWidget(
                number: hand[i].number,
                suit: hand[i].suit,
                width: cardLayout.width,
                height: cardLayout.height,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlayerHandPanel({
    required String playerId,
    required ReplayFrame frame,
    required double handMaxWidth,
    bool compact = false,
  }) {
    final hand = frame.hands[playerId] ?? const <CardWidget>[];
    final meta = _record!.meta;
    final hasDrawRight = frame.hasDrawPrivilege(playerId, meta.playerIds);
    final nameSize = compact ? 10.0 : 12.0;
    final metaSize = compact ? 10.0 : 11.0;

    return Container(
      padding: EdgeInsets.all(compact ? 6 : 8),
      decoration: BoxDecoration(
        color: hasDrawRight ? Colors.orange.withValues(alpha: 0.25) : Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _playerLabel(playerId),
            style: TextStyle(
              color: hasDrawRight ? Colors.orangeAccent : Colors.white,
              fontSize: nameSize,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: compact ? 4 : 6),
          Center(
            child: _buildFaceUpHand(
              hand: hand,
              maxWidth: handMaxWidth,
              compact: compact,
            ),
          ),
          Text(
            '${hand.length}枚',
            style: TextStyle(color: Colors.white54, fontSize: metaSize),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldCard(ReplayFrame frame, ReplayCircleLayout layout) {
    if (frame.fieldNumber < 0 || (frame.fieldSuit == Suit.joker && frame.fieldHistory.isEmpty)) {
      return Container(
        width: layout.layoutFieldCardWidth,
        height: layout.layoutFieldCardHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24),
          borderRadius: BorderRadius.circular(layout.layoutFieldCardWidth * 0.13),
        ),
        child: const Text('—', style: TextStyle(color: Colors.white38)),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CardWidget(
          number: frame.fieldNumber,
          suit: frame.fieldSuit,
          width: layout.layoutFieldCardWidth,
          height: layout.layoutFieldCardHeight,
        ),
        if (frame.fieldHistory.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '履歴 ${frame.fieldHistory.length}枚',
              style: const TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
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
                onPressed: _frameIndex > 0
                    ? () {
                        _stopPlay();
                        _stepBack();
                      }
                    : null,
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
