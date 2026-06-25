import 'package:flutter/material.dart';

import '../replay/replay_circle_layout.dart';
import 'game_board_view.dart';
import 'play_arrow_overlay.dart';

/// 観戦用: 全員の手札を場の周りに固定配置して表示
class SpectatorCircleBoard extends StatefulWidget {
  final List<String> playerIds;
  final Map<String, List<CardWidget>> allPlayerHands;
  final Map<String, int> playerPoints;
  final Set<String> openJokerPlayerIds;
  final int fieldNumber;
  final Suit fieldSuit;
  final String? lastPlayerId;
  final int currentTurnIndex;
  final bool gameStarted;
  final String Function(String) playerLabel;

  const SpectatorCircleBoard({
    super.key,
    required this.playerIds,
    required this.allPlayerHands,
    required this.playerPoints,
    required this.openJokerPlayerIds,
    required this.fieldNumber,
    required this.fieldSuit,
    required this.lastPlayerId,
    required this.currentTurnIndex,
    required this.gameStarted,
    required this.playerLabel,
  });

  @override
  State<SpectatorCircleBoard> createState() => _SpectatorCircleBoardState();
}

class _SpectatorCircleBoardState extends State<SpectatorCircleBoard> {
  final GlobalKey _boardStackKey = GlobalKey();
  final GlobalKey _fieldKey = GlobalKey();
  final Map<String, GlobalKey> _playerPanelKeys = {};

  Offset? _arrowFrom;
  Offset? _arrowTo;
  String? _arrowLabel;

  @override
  void initState() {
    super.initState();
    _syncPlayerPanelKeys();
  }

  @override
  void didUpdateWidget(SpectatorCircleBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPlayerPanelKeys();
    if (oldWidget.lastPlayerId != widget.lastPlayerId ||
        oldWidget.fieldNumber != widget.fieldNumber ||
        oldWidget.playerIds != widget.playerIds) {
      _scheduleArrowMeasure();
    }
  }

  void _syncPlayerPanelKeys() {
    for (final id in widget.playerIds) {
      _playerPanelKeys.putIfAbsent(id, GlobalKey.new);
    }
  }

  void _scheduleArrowMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureArrow());
  }

  void _measureArrow() {
    if (!mounted) return;

    final lastId = widget.lastPlayerId;
    final showArrow = widget.fieldNumber >= 0 &&
        lastId != null &&
        lastId != 'system' &&
        widget.playerIds.contains(lastId);

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

    final label = widget.playerLabel(lastId);

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

  @override
  Widget build(BuildContext context) {
    _scheduleArrowMeasure();

    return LayoutBuilder(
      builder: (context, constraints) {
        final area = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = ReplayCircleLayout.computeForSpectator(
          area: area,
          playerIds: widget.playerIds,
          hands: widget.allPlayerHands,
          openJokerPlayerIds: widget.openJokerPlayerIds,
          gameStarted: widget.gameStarted,
        );

        return Stack(
          key: _boardStackKey,
          clipBehavior: Clip.hardEdge,
          children: [
            for (var i = 0; i < widget.playerIds.length; i++)
              _buildPositionedPlayerPanel(
                playerId: widget.playerIds[i],
                center: layout.playerCenters[i],
                handMaxWidth: layout.handMaxWidth,
                compact: layout.handMaxWidth < 108,
              ),
            Positioned(
              left: layout.fieldCenter.dx - layout.layoutFieldCardWidth / 2,
              top: layout.fieldCenter.dy - layout.layoutFieldCardHeight / 2,
              child: KeyedSubtree(
                key: _fieldKey,
                child: _buildFieldCard(layout),
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
    required Offset center,
    required double handMaxWidth,
    bool compact = false,
  }) {
    final hand = widget.allPlayerHands[playerId] ?? const <CardWidget>[];
    final hasOpenJoker = widget.openJokerPlayerIds.contains(playerId);
    final panelSize = ReplayCircleLayout.panelSizeForSpectator(
      hand,
      handMaxWidth,
      gameStarted: widget.gameStarted,
      hasOpenJoker: hasOpenJoker,
      compact: compact,
    );

    return Positioned(
      left: center.dx - panelSize.width / 2,
      top: center.dy - panelSize.height / 2,
      width: panelSize.width,
      child: KeyedSubtree(
        key: _playerPanelKeys[playerId],
        child: _buildPlayerPanel(
          playerId: playerId,
          handMaxWidth: handMaxWidth,
          compact: compact,
        ),
      ),
    );
  }

  Widget _buildPlayerPanel({
    required String playerId,
    required double handMaxWidth,
    bool compact = false,
  }) {
    final hand = widget.allPlayerHands[playerId] ?? const <CardWidget>[];
    final isActive = widget.playerIds.isNotEmpty &&
        widget.currentTurnIndex % widget.playerIds.length ==
            widget.playerIds.indexOf(playerId);
    final isLastActor = widget.lastPlayerId == playerId;
    final isBurstWarning = hand.length >= 6;
    final hasOpenJoker = widget.openJokerPlayerIds.contains(playerId);
    final nameSize = compact ? 10.0 : 12.0;
    final metaSize = compact ? 10.0 : 11.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: compact ? 4 : 6),
      decoration: BoxDecoration(
        color: isActive ? Colors.orange.withValues(alpha: 0.25) : Colors.black26,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isLastActor ? Colors.amberAccent : Colors.white24,
          width: isLastActor ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.playerLabel(playerId),
            style: TextStyle(
              color: isActive ? Colors.orangeAccent : Colors.white,
              fontSize: nameSize,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.gameStarted)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '${widget.playerPoints[playerId] ?? 0}点',
                style: TextStyle(
                  color: (widget.playerPoints[playerId] ?? 0) >= 0
                      ? Colors.amberAccent
                      : Colors.redAccent,
                  fontSize: metaSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          SizedBox(height: compact ? 4 : 6),
          if (hasOpenJoker)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                'オープンジョーカー',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: metaSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          _buildFaceUpHand(hand: hand, maxWidth: handMaxWidth),
          Text(
            '${hand.length}枚',
            style: TextStyle(
              color: isBurstWarning ? Colors.red : Colors.white54,
              fontSize: metaSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceUpHand({
    required List<CardWidget> hand,
    required double maxWidth,
  }) {
    if (hand.isEmpty) {
      return const SizedBox(
        height: 24,
        child: Center(
          child: Text('手札なし', style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      );
    }

    final cardLayout = HandCardLayout.computeSpectator(
      maxWidth,
      hand.length.clamp(1, 7),
    );

    return SizedBox(
      width: cardLayout.totalWidth(hand.length),
      height: cardLayout.height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
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

  Widget _buildFieldCard(ReplayCircleLayout layout) {
    if (widget.fieldNumber < 0) {
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

    return CardWidget(
      number: widget.fieldNumber,
      suit: widget.fieldSuit,
      width: layout.layoutFieldCardWidth,
      height: layout.layoutFieldCardHeight,
    );
  }
}
