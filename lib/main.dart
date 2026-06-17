import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mori_game/features/auth/app_gate.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
      home: const AppGate(),
    );
  }
}