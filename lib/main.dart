import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:mori_game/features/entrance/entrance_page.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  try {
    await FirebaseAuth.instance.signInAnonymously();
    print("匿名ログインに成功しました！");
  } catch (e) {
    print("ログインエラー: $e");
  }

  runApp(const MoriGameApp());
}

class MoriGameApp extends StatelessWidget {
  const MoriGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mori Game',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.green,
        useMaterial3: true,
      ),
      home: const EntrancePage(),
    );
  }
}