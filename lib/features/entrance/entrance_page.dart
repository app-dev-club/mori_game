import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../logic/room_config.dart';
import '../../services/firebase_db.dart';
import '../../services/firebase_auth_service.dart';
import '../game/game_room_page.dart';

class EntrancePage extends StatefulWidget {
  const EntrancePage({super.key});

  @override
  State<EntrancePage> createState() => _EntrancePageState();
}

class _EntrancePageState extends State<EntrancePage> {
  final TextEditingController _roomIdController = TextEditingController();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _authIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final DatabaseReference _roomsRef = FirebaseDatabase.instance.ref('rooms');

  static const int _maxNameLength = 12;

  @override
  void initState() {
    super.initState();
    FirebaseDB.cleanupOldRooms();
  }

  @override
  void dispose() {
    _roomIdController.dispose();
    _nameController.dispose();
    _authIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<String?> _ensureSignedIn() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid != null) return currentUid;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool busy = false;
        String? error;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> submit({
              required bool isRegister,
            }) async {
              final navigator = Navigator.of(dialogContext);
              final id = _authIdController.text;
              final password = _passwordController.text;

              if (!FirebaseAuthService.isValidId(id)) {
                setDialogState(() {
                  error = 'ユーザーIDは「3〜24文字」「半角英数字と_のみ」です。';
                });
                return;
              }
              if (password.length < 6) {
                setDialogState(() {
                  error = 'パスワードは6文字以上にしてください。';
                });
                return;
              }

              try {
                setDialogState(() {
                  busy = true;
                  error = null;
                });

                if (isRegister) {
                  await FirebaseAuthService.registerWithIdAndPassword(
                    id: id,
                    password: password,
                  );
                } else {
                  await FirebaseAuthService.signInWithIdAndPassword(
                    id: id,
                    password: password,
                  );
                }

                final uid = FirebaseAuth.instance.currentUser?.uid;
                if (!mounted) return;
                if (uid == null) {
                  setDialogState(() => error = 'ログインに失敗しました。');
                  return;
                }
                navigator.pop(uid);
              } catch (e) {
                setDialogState(() {
                  error = e.toString();
                });
              } finally {
                setDialogState(() => busy = false);
              }
            }

            return AlertDialog(
              title: const Text('ログイン / 新規登録'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: _authIdController,
                      style: const TextStyle(color: Colors.black),
                      decoration: const InputDecoration(
                        labelText: 'ユーザーID',
                        hintText: '例: mori_taro',
                      ),
                    ),
                    TextField(
                      controller: _passwordController,
                      style: const TextStyle(color: Colors.black),
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'パスワード',
                      ),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () {
                          Navigator.of(dialogContext).pop(null);
                        },
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: busy ? null : () => submit(isRegister: true),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('新規登録'),
                ),
                FilledButton.tonal(
                  onPressed: busy ? null : () => submit(isRegister: false),
                  child: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ログイン'),
                ),
              ],
            );
          },
        );
      },
    );
  }

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

  void _openRoom(String roomId, {required bool isPrivate, required String userId, int? maxPlayers}) {
    final playerName = _validatedPlayerName();
    if (playerName == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => GameRoomPage(
          roomId: roomId,
          isPrivate: isPrivate,
          playerName: playerName,
          userId: userId,
          maxPlayers: maxPlayers,
        ),
      ),
    );
  }

  Future<void> _createRoom({required bool isPrivate}) async {
    if (_validatedPlayerName() == null) return;
    final uid = await _ensureSignedIn();
    if (uid == null || !mounted) return;

    final maxPlayers = await _showMaxPlayersDialog(isPrivate: isPrivate);
    if (maxPlayers == null || !mounted) return;

    final newRoomId = (Random().nextInt(9000) + 1000).toString();
    _openRoom(newRoomId, isPrivate: isPrivate, userId: uid, maxPlayers: maxPlayers);
  }

  Future<int?> _showMaxPlayersDialog({required bool isPrivate}) {
    int selected = RoomConfig.defaultMaxPlayers;
    final label = isPrivate ? '非公開ルーム' : '公開ルーム';

    return showDialog<int>(
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
                value: selected,
                items: RoomConfig.maxPlayerOptions
                    .map((n) => DropdownMenuItem(value: n, child: Text('$n 人')))
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => selected = value);
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
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: const Text('ルームを作成'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinRoom(String roomId) async {
    if (roomId.isEmpty) return;

    final uid = await _ensureSignedIn();
    if (uid == null || !mounted) return;

    final playerName = _validatedPlayerName();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text('もり - オンラインロビー', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
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
            child: Text('募集中（公開ルーム）', style: TextStyle(color: Colors.white70, fontSize: 16)),
          ),
          Expanded(
            child: StreamBuilder(
              stream: _roomsRef.onValue,
              builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return const Center(child: Text('募集中の部屋はありません', style: TextStyle(color: Colors.white38)));
                }

                Map rooms = snapshot.data!.snapshot.value as Map;

                List<MapEntry> activeRooms = rooms.entries.where((e) {
                  final data = e.value as Map;
                  bool isPrivate = data['isPrivate'] == true;
                  bool isStarted = data['gameStarted'] == true;
                  bool isClosed = data['roomStatus'] == 'closed';
                  bool hasPlayers = data['players'] != null && (data['players'] as List).isNotEmpty;

                  return !isPrivate && !isStarted && !isClosed && hasPlayers;
                }).toList();

                if (activeRooms.isEmpty) {
                  return const Center(child: Text('募集中の部屋はありません', style: TextStyle(color: Colors.white38)));
                }

                return ListView.builder(
                  itemCount: activeRooms.length,
                  itemBuilder: (context, index) {
                    final entry = activeRooms[index];
                    String rid = entry.key.toString();
                    final data = entry.value as Map;
                    final players = data['players'] as List? ?? [];
                    final maxPlayers = RoomConfig.resolveMaxPlayers(data['maxPlayers']);
                    final isFull = RoomConfig.isRoomFull(players.length, maxPlayers);

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      color: Colors.white.withValues(alpha: isFull ? 0.05 : 0.1),
                      child: ListTile(
                        leading: Icon(
                          isFull ? Icons.block : Icons.meeting_room,
                          color: isFull ? Colors.white38 : Colors.orangeAccent,
                        ),
                        title: Text(
                          'ルームID: $rid',
                          style: TextStyle(
                            color: isFull ? Colors.white38 : Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          isFull ? '満員（${players.length}/$maxPlayers 人）' : _formatRoomPlayers(data),
                          style: TextStyle(color: isFull ? Colors.white38 : Colors.white70),
                        ),
                        trailing: Icon(
                          isFull ? Icons.person_off : Icons.arrow_forward_ios,
                          color: isFull ? Colors.white38 : Colors.white,
                          size: 16,
                        ),
                        enabled: !isFull,
                        onTap: isFull ? null : () => _joinRoom(rid),
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
