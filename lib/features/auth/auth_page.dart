import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../effects/app_sound_effects.dart';
import '../../services/firebase_auth_service.dart';
import '../../services/rating_service.dart';
import '../../services/morrie_service.dart';

/// アプリ起動時に表示するログイン / 新規登録画面
class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final TextEditingController _authIdController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final RatingService _ratingService = RatingService();
  final MorrieService _morrieService = MorrieService();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _authIdController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit({required bool isRegister}) async {
    final id = _authIdController.text;
    final password = _passwordController.text;

    if (!FirebaseAuthService.isValidId(id)) {
      setState(() {
        _error = 'ユーザーIDは「3〜24文字」「半角英数字と_のみ」です。';
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _error = 'パスワードは6文字以上にしてください。';
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
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
        setState(() => _error = 'ログインに失敗しました。');
        return;
      }

      await _ratingService.ensureUserRating(uid, displayName: id);
      await _ratingService.ensureBotRatings();
      await _morrieService.ensureBotMorrieRankings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().contains('database.rules')
            ? '$e\n\nターミナルで次を実行してください:\nfirebase deploy --only database'
            : e.toString();
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1B5E20),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'もり',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 42,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'オンライントランプゲーム',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 40),
                  TextField(
                    controller: _authIdController,
                    enabled: !_busy,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black26,
                      labelText: 'ユーザーID',
                      labelStyle: const TextStyle(color: Colors.white70),
                      hintText: '例: mori_taro',
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
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    onSubmitted: (_) => _submit(isRegister: false),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.black26,
                      labelText: 'パスワード',
                      labelStyle: const TextStyle(color: Colors.white70),
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
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                    ),
                  ],
                  const SizedBox(height: 28),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => withButtonSound(() => _submit(isRegister: false)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orangeAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('ログイン', style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => withButtonSound(() => _submit(isRegister: true)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('新規登録', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
