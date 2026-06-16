import 'package:firebase_auth/firebase_auth.dart';

/// Firebase Authentication（メール/パスワード）を
/// 「ユーザーID（メールではない入力）」として使うためのラッパーです。
///
/// 内部的には `ユーザーID@<固定ドメイン>` の形式に変換して
/// email/password で登録・ログインします。
class FirebaseAuthService {
  FirebaseAuthService._();

  // Firebase Auth の「メールアドレス必須」を満たすための固定ドメイン。
  // ここは必要に応じて変更してください。
  static const String _emailDomain = 'mori-game.local';

  static String idToEmail(String id) {
    final normalized = id.trim().toLowerCase();
    return '$normalized@$_emailDomain';
  }

  static bool isValidId(String id) {
    // emailのローカルパートに安全な文字だけに制限します。
    // もし日本語IDなども許可したい場合は設計を見直す必要があります。
    final v = id.trim();
    if (v.length < 3 || v.length > 24) return false;
    final ok = RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(v);
    return ok;
  }

  static Future<UserCredential> registerWithIdAndPassword({
    required String id,
    required String password,
  }) async {
    final email = idToEmail(id);
    return FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  static Future<UserCredential> signInWithIdAndPassword({
    required String id,
    required String password,
  }) async {
    final email = idToEmail(id);
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }
}

