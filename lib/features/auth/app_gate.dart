import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../entrance/entrance_page.dart';
import '../entrance/orphan_room_automation_host.dart';
import 'auth_page.dart';

/// 認証状態に応じてログイン画面またはロビーへ遷移する
class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF1B5E20),
            body: Center(
              child: CircularProgressIndicator(color: Colors.orangeAccent),
            ),
          );
        }
        if (snapshot.data != null) {
          return const OrphanRoomAutomationScope(
            child: EntrancePage(),
          );
        }
        return const AuthPage();
      },
    );
  }
}
