import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 手札・山札・場の矩形から、互いに近い辺同士を結ぶ矢印端点を求める
class PlayArrowGeometry {
  PlayArrowGeometry._();

  static Rect rectInAncestor(RenderBox box, RenderBox ancestor) {
    final topLeft = ancestor.globalToLocal(box.localToGlobal(Offset.zero));
    return topLeft & box.size;
  }

  /// [rect] の縁上で [toward] に最も近い側の点
  static Offset edgeToward(Rect rect, Offset toward) {
    final center = rect.center;
    final dx = toward.dx - center.dx;
    final dy = toward.dy - center.dy;
    if (dx.abs() < 1e-6 && dy.abs() < 1e-6) {
      return center;
    }

    final halfW = rect.width / 2;
    final halfH = rect.height / 2;
    final scaleX = dx.abs() > 1e-6 ? halfW / dx.abs() : double.infinity;
    final scaleY = dy.abs() > 1e-6 ? halfH / dy.abs() : double.infinity;
    final scale = math.min(scaleX, scaleY);
    return Offset(center.dx + dx * scale, center.dy + dy * scale);
  }

  static ({Offset from, Offset to}) betweenRects(Rect fromRect, Rect toRect) {
    return (
      from: edgeToward(fromRect, toRect.center),
      to: edgeToward(toRect, fromRect.center),
    );
  }

  static ({Offset? from, Offset? to}) measureBetween(
    RenderBox stackBox,
    RenderBox? sourceBox,
    RenderBox? targetBox,
  ) {
    if (sourceBox == null || targetBox == null) {
      return (from: null, to: null);
    }
    final endpoints = betweenRects(
      rectInAncestor(sourceBox, stackBox),
      rectInAncestor(targetBox, stackBox),
    );
    return (from: endpoints.from, to: endpoints.to);
  }
}

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
    RenderBox? sourceBox;

    if (lastId == widget.myId) {
      sourceBox = _myHandKey.currentContext?.findRenderObject() as RenderBox?;
    } else if (lastId == 'system') {
      sourceBox = _deckKey.currentContext?.findRenderObject() as RenderBox?;
    } else {
      sourceBox =
          _opponentKeys[lastId]?.currentContext?.findRenderObject() as RenderBox?;
    }

    final endpoints = PlayArrowGeometry.measureBetween(stackBox, sourceBox, fieldBox);
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
    final delta = to - from;
    if (delta.distance < 4) return;

    final linePaint = Paint()
      ..color = Colors.orangeAccent
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, linePaint);

    final angle = math.atan2(delta.dy, delta.dx);
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

    final along = Offset(
      from.dx + delta.dx * 0.38,
      from.dy + delta.dy * 0.38,
    );
    final perpLen = delta.distance;
    final perp = Offset(-delta.dy / perpLen, delta.dx / perpLen);
    final labelCenter = along + perp * 16;

    final labelPos = Offset(
      labelCenter.dx - textPainter.width / 2,
      labelCenter.dy - textPainter.height / 2,
    );
    final bgRect = Rect.fromLTWH(
      labelPos.dx - 6,
      labelPos.dy - 4,
      textPainter.width + 12,
      textPainter.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(8)),
      Paint()..color = Colors.black.withValues(alpha: 0.82),
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
    const headLength = 13.0;
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
