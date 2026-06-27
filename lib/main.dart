import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:mori_game/features/auth/app_gate.dart';
import 'package:mori_game/services/rewarded_ad_service.dart';
import 'package:mori_game/services/sound_settings.dart';
import 'firebase_options.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      // 本番 Web でもコンソールに詳細を出す
      // ignore: avoid_print
      print('FlutterError: ${details.exceptionAsString()}');
    };
    ErrorWidget.builder = (details) {
      return Material(
        color: const Color(0xFF1B5E20),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '画面の描画エラー\n${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    };
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await SoundSettings.instance.load();
    await initializeRewardedAds();
    runApp(const MoriGameApp());
  }, (error, stack) {
    // ignore: avoid_print
    print('Uncaught error: $error\n$stack');
  });
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