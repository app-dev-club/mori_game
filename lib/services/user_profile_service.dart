import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'rating_service.dart';
import 'morrie_service.dart';

/// ユーザーアカウントに紐づくプロフィール（プレイヤー名など）
class UserProfileService {
  static const int maxPlayerNameLength = 12;

  final DatabaseReference _usersRef =
      FirebaseDatabase.instance.ref('users');
  final RatingService _ratingService = RatingService();
  final MorrieService _morrieService = MorrieService();

  Future<String?> getPlayerName(String userId) async {
    try {
      final snap = await _usersRef.child(userId).child('playerName').get();
      final value = snap.value;
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    } catch (_) {
      // read 不可時は未設定扱い
    }
    return null;
  }

  Future<void> savePlayerName(String userId, String playerName) async {
    final trimmed = playerName.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('プレイヤー名が空です');
    }
    if (trimmed.length > maxPlayerNameLength) {
      throw ArgumentError('プレイヤー名は$maxPlayerNameLength文字以内です');
    }

    try {
      await _usersRef.child(userId).update({
        'playerName': trimmed,
        'updatedAt': ServerValue.timestamp,
      });
      await _ratingService.syncPlayerName(userId, trimmed);
      final balance = await _morrieService.getBalance(userId);
      await _morrieService.syncRankingEntry(
        userId,
        morrieBalance: balance,
        playerName: trimmed,
      );
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw Exception(
          'プレイヤー名の保存が拒否されました。Firebase の database.rules をデプロイしてください。',
        );
      }
      rethrow;
    }
  }
}
