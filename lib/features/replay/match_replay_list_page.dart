import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../logic/match_replay_engine.dart';
import '../../models/match_event.dart';
import '../../models/match_record.dart';
import '../../services/game_display_settings.dart';
import '../../services/match_record_service.dart';
import '../common/app_side_bar.dart';
import 'match_replay_page.dart';

class MatchReplayListPage extends StatefulWidget {
  const MatchReplayListPage({super.key});

  @override
  State<MatchReplayListPage> createState() => _MatchReplayListPageState();
}

class _MatchReplayListPageState extends State<MatchReplayListPage> {
  final MatchRecordService _recordService = MatchRecordService();
  final GameDisplaySettings _gameDisplaySettings = GameDisplaySettings();

  bool _hideOpponentNames = false;
  bool _loading = true;
  String? _error;
  List<MatchRecordSummary> _records = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final hide = await _gameDisplaySettings.getHideOpponentNames();
    try {
      final records = await _recordService.listRecentRecords();
      if (!mounted) return;
      setState(() {
        _hideOpponentNames = hide;
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hideOpponentNames = hide;
        _error = formatMatchRecordLoadError(e);
        _loading = false;
      });
    }
  }

  Future<void> _toggleHideOpponentNames() async {
    final next = !_hideOpponentNames;
    setState(() => _hideOpponentNames = next);
    await _gameDisplaySettings.setHideOpponentNames(next);
  }

  void _openReplay(MatchRecordSummary summary) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MatchReplayPage(
          recordId: summary.meta.recordId,
          hideOpponentNames: _hideOpponentNames,
        ),
      ),
    );
  }

  String _formatDate(int ms) {
    if (ms <= 0) return '日時不明';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    final y = dt.year;
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$y/$m/$d $h:$min';
  }

  String _playerSummary(MatchRecordMeta meta) {
    final names = meta.playerIds.map((id) {
      if (_hideOpponentNames) {
        final idx = meta.playerIds.indexOf(id);
        return idx >= 0 ? 'P${idx + 1}' : id;
      }
      return MatchReplayEngine.playerLabel(id, meta);
    });
    return names.join(' / ');
  }

  String _resultSummary(MatchRecordSummary summary) {
    final result = summary.result;
    if (result == null) return '進行中または結果未記録';
    return MatchReplayEngine.resultLabel(result, summary.meta);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text(
          '試合リプレイ',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '再読込',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _buildBody()),
          AppSideBar(
            hideOpponentNames: _hideOpponentNames,
            onToggleHideOpponentNames: _toggleHideOpponentNames,
            items: [
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

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.orangeAccent),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '読み込みに失敗しました',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('再試行')),
          ],
        ),
      );
    }
    if (_records.isEmpty) {
      return const Center(
        child: Text(
          '保存された試合記録がありません',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final summary = _records[index];
        final meta = summary.meta;
        return Material(
          color: Colors.black26,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _openReplay(summary),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ルーム ${meta.roomId} · ${meta.matchIndex}/${meta.seriesTotal} 試合目',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const Icon(Icons.play_circle_outline, color: Colors.orangeAccent),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatDate(meta.startedAtMs),
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _playerSummary(meta),
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _resultSummary(summary),
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
