import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../logic/room_lifecycle.dart';
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

/// ログイン中は常に orphan ルームを監視し、代走が必要な対戦をバックグラウンド進行する
class OrphanRoomAutomationScope extends StatefulWidget {
  final Widget child;

  const OrphanRoomAutomationScope({
    super.key,
    required this.child,
  });

  @override
  State<OrphanRoomAutomationScope> createState() =>
      _OrphanRoomAutomationScopeState();
}

class _OrphanRoomAutomationScopeState extends State<OrphanRoomAutomationScope> {
  static const int _maxAutomatedRooms = 5;

  StreamSubscription<DatabaseEvent>? _roomsSub;
  List<String> _roomIds = [];
  String? _userId;

  @override
  void initState() {
    super.initState();
    _userId = FirebaseAuth.instance.currentUser?.uid;
    _roomsSub = FirebaseDatabase.instance.ref('rooms').onValue.listen(_onRooms);
  }

  @override
  void dispose() {
    _roomsSub?.cancel();
    super.dispose();
  }

  bool _isUserActivelyPlaying(Map<dynamic, dynamic> data, String userId) {
    final players = RoomLifecycle.playerIdsFromData(data);
    if (!players.contains(userId)) return false;
    // presence の同期遅延中でも、参加中かつ離脱扱いでなければ自端末での二重自動進行を防ぐ
    return !RoomLifecycle.afkPlayerIdsFromData(data).contains(userId);
  }

  bool _isUserSpectatingRoom(Map<dynamic, dynamic> data, String userId) {
    final spectators = data['spectators'];
    if (spectators is! Map) return false;
    return spectators.containsKey(userId);
  }

  void _onRooms(DatabaseEvent event) {
    final uid = _userId;
    final raw = event.snapshot.value;
    if (uid == null || raw is! Map) {
      _updateRoomIds(const []);
      return;
    }

    final rooms = Map<dynamic, dynamic>.from(raw);
    final candidates = <String>[];

    for (final entry in rooms.entries) {
      final value = entry.value;
      if (value is! Map) continue;
      final roomData = Map<dynamic, dynamic>.from(value);
      if (!RoomLifecycle.needsBackgroundAutomation(roomData)) continue;
      if (_isUserActivelyPlaying(roomData, uid)) continue;
      if (_isUserSpectatingRoom(roomData, uid)) continue;
      candidates.add(entry.key.toString());
    }

    candidates.sort();
    _updateRoomIds(candidates.take(_maxAutomatedRooms).toList());
  }

  void _updateRoomIds(List<String> next) {
    if (listEquals(_roomIds, next)) return;
    if (!mounted) return;
    setState(() => _roomIds = next);
  }

  @override
  Widget build(BuildContext context) {
    return OrphanRoomAutomationHost(
      roomIds: _roomIds,
      userId: _userId,
      playerName: '自動進行',
      child: widget.child,
    );
  }
}
