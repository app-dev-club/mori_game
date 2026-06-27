import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../effects/app_sound_effects.dart';
import '../../services/game_display_settings.dart';

/// アプリ設定（表示・ログアウト）
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GameDisplaySettings _gameDisplaySettings = GameDisplaySettings();
  bool _hideOpponentNames = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final hide = await _gameDisplaySettings.getHideOpponentNames();
    if (!mounted) return;
    setState(() {
      _hideOpponentNames = hide;
      _loading = false;
    });
  }

  Future<void> _setHideOpponentNames(bool hide) async {
    setState(() => _hideOpponentNames = hide);
    await _gameDisplaySettings.setHideOpponentNames(hide);
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2E7D32),
        title: const Text('ログアウト', style: TextStyle(color: Colors.white)),
        content: const Text(
          'ログアウトしますか？',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'ログアウト',
              style: TextStyle(color: Colors.orangeAccent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      appBar: AppBar(
        title: const Text(
          '設定',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _SettingsSection(
                  title: '表示',
                  children: [
                    SwitchListTile(
                      value: !_hideOpponentNames,
                      onChanged: (showNames) {
                        withButtonSound(() {
                          unawaited(_setHideOpponentNames(!showNames));
                        });
                      },
                      activeThumbColor: Colors.orangeAccent,
                      title: const Text(
                        '対戦相手の名前を表示',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'オフにすると対戦・ランキング・リプレイで相手名が「---」になります',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      secondary: Icon(
                        _hideOpponentNames ? Icons.visibility_off : Icons.visibility,
                        color: _hideOpponentNames ? Colors.amberAccent : Colors.white70,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _SettingsSection(
                  title: 'アカウント',
                  children: [
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.orangeAccent),
                      title: const Text(
                        'ログアウト',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'この端末からサインアウトします',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      onTap: () => withButtonSound(_confirmLogout),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, color: Colors.white12),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}
