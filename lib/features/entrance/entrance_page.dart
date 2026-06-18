import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../logic/room_config.dart';
import '../../services/firebase_db.dart';
import '../../services/game_display_settings.dart';
import '../../services/rating_service.dart';
import '../../services/user_profile_service.dart';
import '../game/game_room_page.dart';
import '../ranking/ranking_page.dart';
import '../common/app_side_bar.dart';

class RoomCreationSettings {
  final int maxPlayers;
  final int totalMatches;

  const RoomCreationSettings({
    required this.maxPlayers,
    required this.totalMatches,
  });
}

class EntrancePage extends StatefulWidget {
  const EntrancePage({super.key});

  @override
  State<EntrancePage> createState() => _EntrancePageState();
}

class _EntrancePageState extends State<EntrancePage> {
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final DatabaseReference _roomsRef = FirebaseDatabase.instance.ref('rooms');
  final RatingService _ratingService = RatingService();
  final UserProfileService _userProfileService = UserProfileService();
  final GameDisplaySettings _gameDisplaySettings = GameDisplaySettings();

  static const int _maxNameLength = UserProfileService.maxPlayerNameLength;
  int? _myRating;
  bool _namePrefilled = false;
  bool _hideOpponentNames = false;

  @override
  void initState() {
    super.initState();
    FirebaseDB.cleanupOldRooms();
    _loadUserProfile();
    _loadDisplaySettings();
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null) return;
      _ratingService.ensureBotRatings();
      _refreshRating();
    });
  }

  Future<void> _loadUserProfile() async {
    final uid = _userId;
    if (uid == null) {
      if (mounted) setState(() => _myRating = null);
      return;
    }

    final playerName = await _userProfileService.getPlayerName(uid);
    final rating = await _ratingService.getRating(uid);
    if (!mounted) return;

    if (!_namePrefilled && playerName != null && playerName.isNotEmpty) {
      _nameController.text = playerName;
      _namePrefilled = true;
    }
    setState(() => _myRating = rating);
  }

  Future<void> _loadDisplaySettings() async {
    final hide = await _gameDisplaySettings.getHideOpponentNames();
    if (!mounted) return;
    setState(() => _hideOpponentNames = hide);
  }

  Future<void> _toggleHideOpponentNames() async {
    await _setHideOpponentNames(!_hideOpponentNames);
  }

  Future<void> _setHideOpponentNames(bool value) async {
    await _gameDisplaySettings.setHideOpponentNames(value);
    if (!mounted) return;
    setState(() => _hideOpponentNames = value);
  }

  Future<void> _refreshRating() async {
    final uid = _userId;
    if (uid == null) return;
    final rating = await _ratingService.getRating(uid);
    if (mounted) setState(() => _myRating = rating);
  }

  @override
  void dispose() {
    _roomIdController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  String? get _userId => FirebaseAuth.instance.currentUser?.uid;

  String? _validatedPlayerName() {
    final trimmed = _nameController.text.trim();
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プレイヤー名を入力してください')),
      );
      return null;
    }
    if (trimmed.length > _maxNameLength) {
      return trimmed.substring(0, _maxNameLength);
    }
    return trimmed;
  }

  Future<String?> _validatedAndSavedPlayerName() async {
    final playerName = _validatedPlayerName();
    if (playerName == null) return null;

    final uid = _userId;
    if (uid != null) {
      try {
        await _userProfileService.savePlayerName(uid, playerName);
      } catch (e) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
        return null;
      }
    }
    return playerName;
  }

  Future<void> _openRoom(
    String roomId, {
    required bool isPrivate,
    required String userId,
    int? maxPlayers,
    int? totalMatches,
  }) async {
    final playerName = await _validatedAndSavedPlayerName();
    if (playerName == null || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameRoomPage(
          roomId: roomId,
          isPrivate: isPrivate,
          playerName: playerName,
          userId: userId,
          maxPlayers: maxPlayers,
          totalMatches: totalMatches,
        ),
      ),
    );
  }

  Future<void> _createRoom({required bool isPrivate}) async {
    if (_validatedPlayerName() == null) return;
    final uid = _userId;
    if (uid == null) return;

    final settings = await _showRoomCreationDialog(isPrivate: isPrivate);
    if (settings == null || !mounted) return;

    final newRoomId = (Random().nextInt(9000) + 1000).toString();
    await _openRoom(
      newRoomId,
      isPrivate: isPrivate,
      userId: uid,
      maxPlayers: settings.maxPlayers,
      totalMatches: settings.totalMatches,
    );
  }

  Future<RoomCreationSettings?> _showRoomCreationDialog({required bool isPrivate}) {
    int selectedMaxPlayers = RoomConfig.defaultMaxPlayers;
    int selectedMatchCount = RoomConfig.defaultMatchCount;
    final label = isPrivate ? '非公開ルーム' : '公開ルーム';

    return showDialog<RoomCreationSettings>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('$labelを作成'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('最大入室人数を選んでください'),
              const SizedBox(height: 16),
              DropdownButton<int>(
                isExpanded: true,
                value: selectedMaxPlayers,
                items: RoomConfig.maxPlayerOptions
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n 人')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => selectedMaxPlayers = value);
                },
              ),
              const SizedBox(height: 20),
              const Text('対戦回数を選んでください'),
              const SizedBox(height: 8),
              const Text(
                '2回以上の場合、各対戦後は意思確認なしで自動的に次の対戦へ進みます。',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              DropdownButton<int>(
                isExpanded: true,
                value: selectedMatchCount,
                items: RoomConfig.matchCountOptions
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n 回')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => selectedMatchCount = value);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                RoomCreationSettings(
                  maxPlayers: selectedMaxPlayers,
                  totalMatches: selectedMatchCount,
                ),
              ),
              child: const Text('ルームを作成'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinRoom(String roomId) async {
    if (roomId.isEmpty) return;

    final uid = _userId;
    if (uid == null) return;

    final playerName = await _validatedAndSavedPlayerName();
    if (playerName == null) return;

    final db = FirebaseDB(roomId);
    final snapshot = await db.getSnapshot();

    if (snapshot.exists) {
      bool isStarted = snapshot.child('gameStarted').value == true;
      String status = snapshot.child('roomStatus').value as String? ?? 'open';

      if (status == 'closed' || isStarted) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('その部屋は既に開始されているか、閉鎖されています')),
        );
        return;
      }

      final players = snapshot.child('players').value as List? ?? [];
      final maxPlayers = RoomConfig.resolveMaxPlayers(snapshot.child('maxPlayers').value);
      if (RoomConfig.isRoomFull(players.length, maxPlayers)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('その部屋は定員（$maxPlayers人）に達しています')),
        );
        return;
      }
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameRoomPage(
          roomId: roomId,
          playerName: playerName,
          userId: uid,
        ),
      ),
    );
  }

  String _formatRoomPlayers(Map data) {
    final players = data['players'] as List?;
    if (players == null || players.isEmpty) return '待機中: 0 人';

    final maxPlayers = RoomConfig.resolveMaxPlayers(data['maxPlayers']);
    final countLabel = '${players.length}/$maxPlayers 人';

    final namesRaw = data['playerNames'];
    if (namesRaw is! Map) return '待機中: $countLabel';

    final names = namesRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
    final labels = players.map((id) {
      final name = names[id.toString()];
      return (name != null && name.isNotEmpty) ? name : 'プレイヤー';
    }).join('、');

    return '待機中: $countLabel（$labels）';
  }

  bool _isPublicRoomVisible(Map data) {
    if (data['isPrivate'] == true) return false;
    if (data['roomDismissedByHost'] == true) return false;

    final players = data['players'] as List?;
    if (players == null || players.isEmpty) return false;

    final isStarted = data['gameStarted'] == true;
    final status = data['roomStatus'] as String? ?? 'open';

    if (isStarted) return true;
    if (!isStarted && status == 'open') return true;
    return false;
  }

  String _roomListSubtitle(Map data) {
    final players = data['players'] as List? ?? [];
    final maxPlayers = RoomConfig.resolveMaxPlayers(data['maxPlayers']);
    final countLabel = '${players.length}/$maxPlayers 人';
    final isStarted = data['gameStarted'] == true;
    final isFull = RoomConfig.isRoomFull(players.length, maxPlayers);

    if (isStarted) {
      final totalMatches = RoomConfig.resolveMatchCount(data['totalMatches']);
      final completedMatches = RoomConfig.resolveNonNegativeInt(data['completedMatches']);
      if (totalMatches > 1) {
        return '対戦中: $countLabel · 第${completedMatches + 1}戦 / 全$totalMatches戦';
      }
      return '対戦中: $countLabel';
    }
    if (isFull) return '満員（$countLabel）';
    return _formatRoomPlayers(data);
  }

  int _roomListSortOrder(Map data) {
    final isStarted = data['gameStarted'] == true;
    if (isStarted) return 2;

    final players = data['players'] as List? ?? [];
    final maxPlayers = RoomConfig.resolveMaxPlayers(data['maxPlayers']);
    if (RoomConfig.isRoomFull(players.length, maxPlayers)) return 1;
    return 0;
  }

  void _openRanking() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RankingPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: Column(
          children: [
            const Text('もり - オンラインロビー',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            if (_myRating != null)
              Text(
                'レート $_myRating',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
              ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: TextField(
              controller: _nameController,
              maxLength: _maxNameLength,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                counterStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Colors.black26,
                labelText: 'プレイヤー名',
                labelStyle: const TextStyle(color: Colors.white70),
                hintText: '例: もり太郎',
                hintStyle: const TextStyle(color: Colors.white38),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Colors.orangeAccent),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildActionBtn('公開で作成', Icons.public, Colors.orangeAccent, () => _createRoom(isPrivate: false)),
              const SizedBox(width: 15),
              _buildActionBtn('非公開で作成', Icons.lock, Colors.blueGrey, () => _createRoom(isPrivate: true)),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24, indent: 40, endIndent: 40),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('公開ルーム', style: TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          Expanded(
            child: StreamBuilder(
              stream: _roomsRef.onValue,
              builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return const Center(child: Text('公開ルームはありません', style: TextStyle(color: Colors.white38)));
                }

                Map rooms = snapshot.data!.snapshot.value as Map;

                List<MapEntry> publicRooms = rooms.entries
                    .where((e) => _isPublicRoomVisible(e.value as Map))
                    .toList()
                  ..sort((a, b) {
                    final order = _roomListSortOrder(a.value as Map)
                        .compareTo(_roomListSortOrder(b.value as Map));
                    if (order != 0) return order;
                    return a.key.toString().compareTo(b.key.toString());
                  });

                if (publicRooms.isEmpty) {
                  return const Center(child: Text('公開ルームはありません', style: TextStyle(color: Colors.white38)));
                }

                return ListView.builder(
                  itemCount: publicRooms.length,
                  itemBuilder: (context, index) {
                    final entry = publicRooms[index];
                    String rid = entry.key.toString();
                    final data = entry.value as Map;
                    final players = data['players'] as List? ?? [];
                    final maxPlayers = RoomConfig.resolveMaxPlayers(data['maxPlayers']);
                    final isStarted = data['gameStarted'] == true;
                    final isFull = RoomConfig.isRoomFull(players.length, maxPlayers);
                    final canJoin = !isStarted && !isFull;

                    final Color cardColor;
                    final Color titleColor;
                    final IconData leadingIcon;
                    final Color leadingColor;
                    final String? statusBadge;

                    if (isStarted) {
                      cardColor = Colors.blue.withValues(alpha: 0.12);
                      titleColor = Colors.white;
                      leadingIcon = Icons.sports_esports;
                      leadingColor = Colors.lightBlueAccent;
                      statusBadge = '対戦中';
                    } else if (isFull) {
                      cardColor = Colors.orange.withValues(alpha: 0.12);
                      titleColor = Colors.white;
                      leadingIcon = Icons.groups;
                      leadingColor = Colors.orangeAccent;
                      statusBadge = '満員';
                    } else {
                      cardColor = Colors.white.withValues(alpha: 0.1);
                      titleColor = Colors.white;
                      leadingIcon = Icons.meeting_room;
                      leadingColor = Colors.orangeAccent;
                      statusBadge = null;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      color: cardColor,
                      child: ListTile(
                        leading: Icon(leadingIcon, color: leadingColor),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'ルームID: $rid',
                                style: TextStyle(
                                  color: titleColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            if (statusBadge != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: leadingColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: leadingColor.withValues(alpha: 0.6)),
                                ),
                                child: Text(
                                  statusBadge,
                                  style: TextStyle(
                                    color: leadingColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          _roomListSubtitle(data),
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: Icon(
                          canJoin ? Icons.arrow_forward_ios : Icons.visibility,
                          color: canJoin ? Colors.white : Colors.white54,
                          size: 16,
                        ),
                        enabled: canJoin,
                        onTap: canJoin ? () => _joinRoom(rid) : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
          _buildBottomBar(),
        ],
            ),
          ),
          _buildSideTabs(),
        ],
      ),
    );
  }

  Widget _buildSideTabs() {
    return AppSideBar(
      hideOpponentNames: _hideOpponentNames,
      onToggleHideOpponentNames: _toggleHideOpponentNames,
      items: [
        AppSideBarItem(
          label: 'ランキング',
          icon: Icons.leaderboard,
          accent: Colors.amberAccent,
          onTap: _openRanking,
        ),
        AppSideBarItem(
          label: 'ログアウト',
          icon: Icons.logout,
          onTap: () => FirebaseAuth.instance.signOut(),
        ),
      ],
    );
  }

  Widget _buildActionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: const BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _roomIdController,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'ルームIDを入力して合流',
                hintStyle: TextStyle(color: Colors.white38),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => _joinRoom(_roomIdController.text),
            child: const Text('合流'),
          ),
        ],
      ),
    );
  }
}
