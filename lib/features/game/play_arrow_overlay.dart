import 'dart:math' as math;
import 'package:flutter/material.dart';

enum _Anchor { topCenter, bottomCenter, center, centerRight }

/// 場のカードと出したプレイヤーを矢印で結ぶオーバーレイ
class PlayArrowOverlay extends StatefulWidget {
  final String? lastPlayerId;
  final String myId;
  final List<String> playerIds;
  final int fieldNumber;
  final String Function(String?) playerLabel;
  final Widget Function({
    required GlobalKey fieldKey,
    required GlobalKey deckKey,
    required GlobalKey myHandKey,
    required Map<String, GlobalKey> opponentKeys,
  }) builder;

  const PlayArrowOverlay({
    super.key,
    required this.lastPlayerId,
    required this.myId,
    required this.playerIds,
    required this.fieldNumber,
    required this.playerLabel,
    required this.builder,
  });

  @override
  State<PlayArrowOverlay> createState() => _PlayArrowOverlayState();
}

class _PlayArrowOverlayState extends State<PlayArrowOverlay> {
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _fieldKey = GlobalKey();
  final GlobalKey _deckKey = GlobalKey();
  final GlobalKey _myHandKey = GlobalKey();
  final Map<String, GlobalKey> _opponentKeys = {};

  Offset? _arrowFrom;
  Offset? _arrowTo;
  String? _arrowLabel;

  @override
  void initState() {
    super.initState();
    _syncOpponentKeys();
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(PlayArrowOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncOpponentKeys();
    if (oldWidget.lastPlayerId != widget.lastPlayerId ||
        oldWidget.fieldNumber != widget.fieldNumber ||
        oldWidget.playerIds != widget.playerIds) {
      _scheduleMeasure();
    }
  }

  void _syncOpponentKeys() {
    for (final id in widget.playerIds) {
      if (id == widget.myId) continue;
      _opponentKeys.putIfAbsent(id, GlobalKey.new);
    }
  }

  void _scheduleMeasure() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureArrow());
  }

  Offset? _anchorInStack(RenderBox source, RenderBox stack, _Anchor anchor) {
    final local = switch (anchor) {
      _Anchor.topCenter => Offset(source.size.width / 2, 0),
      _Anchor.bottomCenter => Offset(source.size.width / 2, source.size.height),
      _Anchor.center => source.size.center(Offset.zero),
      _Anchor.centerRight => Offset(source.size.width, source.size.height / 2),
    };
    return stack.globalToLocal(source.localToGlobal(local));
  }

  void _measureArrow() {
    if (!mounted) return;

    if (widget.fieldNumber == -1 || widget.lastPlayerId == null) {
      if (_arrowFrom != null || _arrowTo != null) {
        setState(() {
          _arrowFrom = null;
          _arrowTo = null;
          _arrowLabel = null;
        });
      }
      return;
    }

    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || fieldBox == null) return;

    final lastId = widget.lastPlayerId!;
    Offset? from;
    Offset? to;

    if (lastId == widget.myId) {
      final myBox = _myHandKey.currentContext?.findRenderObject() as RenderBox?;
      if (myBox == null) return;
      from = _anchorInStack(myBox, stackBox, _Anchor.topCenter);
      to = _anchorInStack(fieldBox, stackBox, _Anchor.bottomCenter);
    } else if (lastId == 'system') {
      final deckBox = _deckKey.currentContext?.findRenderObject() as RenderBox?;
      if (deckBox == null) return;
      from = _anchorInStack(deckBox, stackBox, _Anchor.centerRight);
      to = _anchorInStack(fieldBox, stackBox, _Anchor.center);
    } else {
      final opponentBox =
          _opponentKeys[lastId]?.currentContext?.findRenderObject() as RenderBox?;
      if (opponentBox == null) return;
      from = _anchorInStack(opponentBox, stackBox, _Anchor.bottomCenter);
      to = _anchorInStack(fieldBox, stackBox, _Anchor.topCenter);
    }

    final label = widget.playerLabel(lastId);
    if (from == null || to == null) return;

    if (_offsetNear(from, _arrowFrom) && _offsetNear(to, _arrowTo) && label == _arrowLabel) {
      return;
    }

    setState(() {
      _arrowFrom = from;
      _arrowTo = to;
      _arrowLabel = label;
    });
  }

  bool _offsetNear(Offset a, Offset? b) {
    if (b == null) return false;
    return (a - b).distance < 2;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureArrow());
    return Stack(
      key: _stackKey,
      children: [
        widget.builder(
          fieldKey: _fieldKey,
          deckKey: _deckKey,
          myHandKey: _myHandKey,
          opponentKeys: _opponentKeys,
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
  }
}

class PlayArrowPainter extends CustomPainter {
  final Offset from;
  final Offset to;
  final String label;

  PlayArrowPainter({
    required this.from,
    required this.to,
    required this.label,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final control = Offset(
      (from.dx + to.dx) / 2 + (from.dy - to.dy) * 0.08,
      (from.dy + to.dy) / 2,
    );

    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..quadraticBezierTo(control.dx, control.dy, to.dx, to.dy);

    final linePaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, linePaint);

    final tangent = Offset(to.dx - control.dx, to.dy - control.dy);
    final angle = math.atan2(tangent.dy, tangent.dx);
    _drawArrowHead(canvas, to, angle, linePaint.color);

    if (label.isEmpty) return;

    final textSpan = TextSpan(
      text: label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final labelPos = Offset(
      control.dx - textPainter.width / 2,
      control.dy - textPainter.height - 10,
    );
    final bgRect = Rect.fromLTWH(
      labelPos.dx - 6,
      labelPos.dy - 4,
      textPainter.width + 12,
      textPainter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(8)),
      Paint()..color = Colors.black.withValues(alpha: 0.75),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(8)),
      Paint()
        ..color = Colors.orangeAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    textPainter.paint(canvas, labelPos);
  }

  void _drawArrowHead(Canvas canvas, Offset tip, double angle, Color color) {
    const headLength = 14.0;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(
        tip.dx - headLength * math.cos(angle - math.pi / 7),
        tip.dy - headLength * math.sin(angle - math.pi / 7),
      )
      ..lineTo(
        tip.dx - headLength * math.cos(angle + math.pi / 7),
        tip.dy - headLength * math.sin(angle + math.pi / 7),
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant PlayArrowPainter oldDelegate) {
    return oldDelegate.from != from ||
        oldDelegate.to != to ||
        oldDelegate.label != label;
  }
}
