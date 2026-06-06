# Mori_game
## 環境構築
### Git関係のインストール
- GitHubアカウントの作成
- GitBash等をインストール
- PowerShellで以下を実行
  - `ssh-keygen -t ed25519 -C "あなたのGitHubメール"`
  - `Get-Content $env:USERPROFILE\.ssh\id_ed25519.pub`
    - でてきた文字をコピー（あとで貼る）
- GitHubのSettings → SSH and GPG keys → New SSH key に貼り付ける
- ふたたびPowerShellで以下を実行
  - `ssh -T git@github.com`
- その後Gitbashで
  - `git clone git@github.com:app-dev-club/mori_game.git`
  - これでプロジェクトがコピーされる。
### 必要なファイルの準備
- セキュリティの問題上GitHubに上げていないファイルを準備する
### Flutterのインストール
1. 開発環境のインストール
- まずは自分のPCに道具を揃えます。
  - Flutter SDK: [公式サイトから](https://docs.flutter.dev/install)自分のOS（WindowsかMacか）に合わせてダウンロードします。
    - [クイックスタート](https://docs.flutter.dev/install/quick)からダウンロード
    - 基本的にここの手順に従う
  - Editor: VS Code (Visual Studio Code) が最も軽量でおすすめです。「Flutter」と「Dart」の拡張機能をインストールしてください。
  - Android Studio: Androidアプリをビルドするために必要です。インストール後、Android SDK と Command-line Tools をセットアップします。
    - 起動画面からMore Antions > SDK Managerを選択
      - Android SDKのSDK ToolsタブからCommand-line Tools (latest)を探してチェック入れる
    - flutter config --android-sdk "コピーしたパス"
    - flutter doctor --android-licenses
  - XCode 将来的に使用予定（Macのみ）
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
### Cursorのインストール
- AIとプログラムを書くならCursor等インストールする
  - Claude Codeなど、他にも色々あるのでお金と機能を考えながらインストール
## 更新後のビルド手順
- `flutter build web`
- `firebase deploy --only hosting`
## ローカルでの動作確認
- `flutter run -d chrome`