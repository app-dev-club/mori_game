import 'package:flutter/material.dart';

class OthersStatusView extends StatelessWidget {
  final List<String> playerIds;
  final String myId;
  final Map<String, int> handCounts;
  final int currentTurnIndex;

  const OthersStatusView({
    super.key,
    required this.playerIds,
    required this.myId,
    required this.handCounts,
    required this.currentTurnIndex,
  });

  @override
  Widget build(BuildContext context) {
    final others = playerIds.where((id) => id != myId).toList();
    final activePlayerId = playerIds.isNotEmpty 
        ? playerIds[currentTurnIndex % playerIds.length] 
        : "";

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: others.map((id) {
          bool isHisTurn = (id == activePlayerId);
          int count = handCounts[id] ?? 0;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Column(
              children: [
                CircleAvatar(
                  backgroundColor: isHisTurn ? Colors.orange : Colors.grey[700],
                  radius: 18,
                  child: Icon(Icons.person, color: isHisTurn ? Colors.white : Colors.white54, size: 20),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$count 枚', 
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}