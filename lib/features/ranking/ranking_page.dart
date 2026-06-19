import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../logic/player_display_name.dart';
import '../../models/ranking_entry.dart';
import '../../services/game_display_settings.dart';
import '../../services/rating_service.dart';
import '../common/app_side_bar.dart';

class RankingPage extends StatefulWidget {
  const RankingPage({super.key});

  @override
  State<RankingPage> createState() => _RankingPageState();
}

class _RankingPageState extends State<RankingPage> {
  final GameDisplaySettings _gameDisplaySettings = GameDisplaySettings();
  final RatingService _ratingService = RatingService();
  bool _hideOpponentNames = false;

  @override
  void initState() {
    super.initState();
    _loadDisplaySettings();
  }

  Future<void> _loadDisplaySettings() async {
    final hide = await _gameDisplaySettings.getHideOpponentNames();
    if (!mounted) return;
    setState(() => _hideOpponentNames = hide);
  }

  Future<void> _toggleHideOpponentNames() async {
    final next = !_hideOpponentNames;
    setState(() => _hideOpponentNames = next);
    await _gameDisplaySettings.setHideOpponentNames(next);
  }

  Color _rankColor(int rank) {
    if (rank == 1) return const Color(0xFFFFD54F);
    if (rank == 2) return const Color(0xFFB0BEC5);
    if (rank == 3) return const Color(0xFFCD7F32);
    return Colors.white70;
  }

  IconData? _rankIcon(int rank) {
    if (rank == 1) return Icons.emoji_events;
    if (rank == 2) return Icons.emoji_events_outlined;
    if (rank == 3) return Icons.emoji_events_outlined;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final myId = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text(
          'レートランキング',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: StreamBuilder<List<RankingEntry>>(
              stream: _ratingService.watchRanking(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.orangeAccent),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'ランキングの取得に失敗しました\n${snapshot.error}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  );
                }

                final entries = snapshot.data ?? [];
                if (entries.isEmpty) {
                  return const Center(
                    child: Text(
                      'まだランキングデータがありません',
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: entries.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final isMe = myId != null && entry.id == myId;
                    final rankColor = _rankColor(entry.rank);
                    final rankIcon = _rankIcon(entry.rank);
                    final displayName = PlayerDisplayName.resolveForRanking(
                      entry: entry,
                      myId: myId,
                      hideOpponentNames: _hideOpponentNames,
                    );

                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: isMe ? Colors.orange.withValues(alpha: 0.18) : Colors.black26,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isMe ? Colors.orangeAccent : Colors.white12,
                          width: isMe ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 42,
                            child: rankIcon != null
                                ? Icon(rankIcon, color: rankColor, size: 26)
                                : Text(
                                    '${entry.rank}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: rankColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 18,
                                    ),
                                  ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  displayName,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: isMe ? FontWeight.bold : FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                if (entry.isBot)
                                  const Text(
                                    'Bot',
                                    style: TextStyle(color: Colors.white38, fontSize: 11),
                                  )
                                else if (isMe)
                                  const Text(
                                    'あなた',
                                    style: TextStyle(color: Colors.orangeAccent, fontSize: 11),
                                  ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${entry.rating}',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 20,
                                ),
                              ),
                              Text(
                                '${entry.gamesPlayed}戦',
                                style: const TextStyle(color: Colors.white38, fontSize: 11),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          AppSideBar(
            hideOpponentNames: _hideOpponentNames,
            onToggleHideOpponentNames: _toggleHideOpponentNames,
            items: [
              AppSideBarItem(
                label: 'ランキング',
                icon: Icons.leaderboard,
                accent: Colors.amberAccent,
                onTap: () {},
              ),
              AppSideBarItem(
                label: 'ログアウト',
                icon: Icons.logout,
                onTap: () => FirebaseAuth.instance.signOut(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
