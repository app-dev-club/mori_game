import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart'; // flutterfire configureで生成されたファイル
import 'package:mori_game/pages/GamePage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // ↓ これを追加！ URLは Firebase Console の Realtime Database 画面上部にある
  // https://[プロジェクト名]-default-rtdb.firebaseio.com/ のような形式のものです。
  FirebaseDatabase.instance.databaseURL = "https://mori-game-default-rtdb.asia-southeast1.firebasedatabase.app/";

  runApp(const MoriApp());
}

class MoriApp extends StatelessWidget {
  const MoriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'もり - リアルタイム対戦',
      theme: ThemeData(primarySwatch: Colors.green), // トランプっぽく緑
      home: GamePage(),
    );
  }
}