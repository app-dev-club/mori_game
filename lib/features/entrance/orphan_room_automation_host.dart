import 'package:flutter/material.dart';

import '../game/game_room_page.dart';

/// 接続者がいない対戦中ルームの Bot / 代走をバックグラウンドで進める
class OrphanRoomAutomationHost extends StatelessWidget {
  final List<String> roomIds;
  final String? userId;
  final String playerName;
  final Widget child;

  const OrphanRoomAutomationHost({
    super.key,
    required this.roomIds,
    required this.userId,
    required this.playerName,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (userId == null || roomIds.isEmpty) return child;

    return Stack(
      children: [
        child,
        for (final roomId in roomIds)
          Offstage(
            offstage: true,
            child: GameRoomPage(
              key: ValueKey('orphan_automation_$roomId'),
              roomId: roomId,
              userId: userId,
              playerName: playerName,
              automationOnly: true,
            ),
          ),
      ],
    );
  }
}
