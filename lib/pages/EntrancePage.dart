import 'package:flutter/material.dart';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:mori_game/services/FirebaseService.dart';
import 'GameController.dart';

class EntrancePage extends StatefulWidget {
  const EntrancePage({super.key});

  @override
  State<EntrancePage> createState() => _EntrancePageState();
}

class _EntrancePageState extends State<EntrancePage> {
  final TextEditingController _controller = TextEditingController();
  final DatabaseReference _roomsRef = FirebaseDatabase.instance.ref('rooms');

  // ルーム作成（4桁ランダム）
  void _createRoom() {
    String newRoomId = (Random().nextInt(9000) + 1000).toString();
    _joinRoom(newRoomId);
  }

  // 指定したIDの部屋へ遷移
  void _joinRoom(String roomId) async {
    if (roomId.isEmpty) return;

    final db = FirebaseService(roomId);
    final snapshot = await db.getRoomSnapshot();
    
    if (snapshot.exists && snapshot.child('gameStarted').value == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('その部屋は既にゲームが開始されています')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => GameController(roomId: roomId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text('もり - オンラインロビー', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 20),
          // --- ルーム作成エリア ---
          ElevatedButton.icon(
            onPressed: _createRoom,
            icon: const Icon(Icons.add),
            label: const Text('自分で部屋を作る'),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(250, 50),
              backgroundColor: Colors.orangeAccent,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          const Divider(color: Colors.white24, indent: 40, endIndent: 40),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Text('現在募集中の部屋', style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          
          // --- 公開ルーム一覧 (StreamBuilderでリアルタイム表示) ---
          Expanded(
            child: StreamBuilder(
              stream: _roomsRef.onValue,
              builder: (context, AsyncSnapshot<DatabaseEvent> snapshot) {
                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return const Center(child: Text('開いている部屋はありません', style: TextStyle(color: Colors.white38)));
                }

                Map<dynamic, dynamic> rooms = snapshot.data!.snapshot.value as Map;
                List<MapEntry<dynamic, dynamic>> activeRooms = rooms.entries.where((entry) {
                  final data = entry.value as Map;
                  // 「ゲーム開始前」かつ「プレイヤーが存在する」部屋のみ表示
                  return data['gameStarted'] == false && data['players'] != null;
                }).toList();

                if (activeRooms.isEmpty) {
                  return const Center(child: Text('募集中の部屋はありません', style: TextStyle(color: Colors.white38)));
                }

                return ListView.builder(
                  itemCount: activeRooms.length,
                  itemBuilder: (context, index) {
                    String roomId = activeRooms[index].key.toString();
                    Map data = activeRooms[index].value as Map;
                    int playerCount = (data['players'] as List).length;

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      color: Colors.white.withOpacity(0.1),
                      child: ListTile(
                        leading: const Icon(Icons.meeting_room, color: Colors.orangeAccent),
                        title: Text('ルームID: $roomId', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        subtitle: Text('待機人数: $playerCount 人', style: const TextStyle(color: Colors.white70)),
                        trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                        onTap: () => _joinRoom(roomId),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          
          // --- 直接入力エリア ---
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: '直接ID入力',
                      hintStyle: TextStyle(color: Colors.white38),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: () => _joinRoom(_controller.text),
                  child: const Text('入室'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}