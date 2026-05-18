# Mori_game
## 環境構築
1. 開発環境のインストール
- まずは自分のPCに道具を揃えます。
  - Flutter SDK: [公式サイトから](https://docs.flutter.dev/install)自分のOS（WindowsかMacか）に合わせてダウンロードします。
  - Editor: VS Code (Visual Studio Code) が最も軽量でおすすめです。「Flutter」と「Dart」の拡張機能をインストールしてください。
  - Android Studio: Androidアプリをビルドするために必要です。インストール後、Android SDK と Command-line Tools をセットアップします。
    - 起動画面からMore Antions > SDK Managerを選択
      - Android SDKのSDK ToolsタブからCommand-line Tools (latest)を探してチェック入れる
    - flutter config --android-sdk "コピーしたパス"
    - flutter doctor --android-licenses
  - XCode 将来的に使用予定
    - sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
    - sudo xcodebuild -runFirstLaunch
    - cocoapadsインストール
      - brew install cocoapods
  - Google Chrome: Web版の動作確認用に使用します。
  - Check!: ターミナル（またはコマンドプロンプト）で flutter doctor と入力してください。すべてにチェック（✔）がつけば準備完了です。

2. Firebaseプロジェクトの作成
  - リアルタイム対戦のバックエンドとしてFirebaseを紐付けます。
  - [Firebase Console](https://console.firebase.google.com/u/0/) にアクセス。
  - 「プロジェクトを追加」をクリック（名前は「mori-game」など）。
- Google Analytics は、将来の分析のためにONにしておくと良いです。

3. Flutterプロジェクトとの紐付け（ここが重要！）
  - 最近は FlutterFire CLI を使うのが最も簡単で確実です。
  - Firebase CLIをインストール:
    - npm install -g firebase-tools （Node.jsが入っている場合）
  - Firebaseにログイン:
    - firebase login
  - FlutterFire CLIをインストール:
    - dart pub global activate flutterfire_cli
  - プロジェクトの初期化:
    - 作りたいプロジェクト内で`flutter create .`
    - Flutterプロジェクトのフォルダ内で以下を実行します。
      - flutterfire configure
        - ここで、作成したFirebaseプロジェクトを選択し、「android」と「web」にチェックを入れます。これにより、設定ファイル（google-services.json など）が自動生成されます。
4. 必要なパッケージの導入
  - flutter pub add firebase_core
5. 動作確認
  - flutter run -d chrome
