# Mori_game
## 環境構築
### 目標
- 自分のPC(パワーシェル)で以下が実行できるようになる。
  - `git clone git@github.com:app-dev-club/mori_game.git`
    -　開発した「もり」のファイルのダウンロード
  - `flutter run -d chrome`
    - 開発したもりプログラムの動作確認
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
  - 上記コマンドを実行したディレクトリに保存されるので、 `cd`コマンドを使って任意の場所に移動してからコマンドを実行する。
### エディタのインストール
- VSCodeがおすすめ
- AIとプログラムを書くならCursor等インストールする
  - Claude Codeなど、他にも色々あるのでお金と機能を考えながらインストール
### Flutterのインストール
1. 開発環境のインストール
- まずは自分のPCに道具を揃えます。
  - Flutter SDK: [公式サイトから](https://docs.flutter.dev/install)自分のOS（WindowsかMacか）に合わせてダウンロードします。
    - [クイックスタート](https://docs.flutter.dev/install/quick)からダウンロード
    - 基本的に上記リンクの手順に従う
  - Editor: VS Code (Visual Studio Code)で「Flutter」と「Dart」の拡張機能をインストールしてください。
  - Android Studio: Androidアプリをビルドするために必要です。インストール後、Android SDK と Command-line Tools をセットアップします。
    - SDK Managerを選択（バージョンによって場所が異なる）
      - Android SDKのSDK ToolsタブからCommand-line Tools (latest)を探してチェック入れる
    - flutter config --android-sdk "コピーしたパス"
      - Windowsなら `C:\Users\ユーザ名\AppData\Local\Android\Sdk` など
    - flutter doctor --android-licenses
  - XCode 将来的に使用予定（Macのみ）
    - sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
    - sudo xcodebuild -runFirstLaunch
    - cocoapadsインストール
      - brew install cocoapods
  - Google Chrome: Web版の動作確認用に使用します。
  - Check!: ターミナル（またはコマンドプロンプト）で flutter doctor と入力してください。すべてにチェック（✔）がつけば準備完了です。
- 開発者モードをオン
  - start ms-settings:developers
### Firebase関連のインストール
- 自分のGoogleアカウントにFirebaseの編集権を付与してもらう
  - 通知メールから招待に応じる
- Firebase CLIをインストール:
    - npm install -g firebase-tools （Node.jsが入っている場合）
- Firebaseにログイン:
  - firebase login
  - 質問には`y`でEnterして大丈夫
  - 編集権を付与してもらったアカウントにログイン
- FlutterFire CLIをアクティベート:
  - dart pub global run flutterfire_cli:flutterfire configure
    - 最初の質問で`n`を押す
    - プラットフォームの選択では矢印キーで移動、スペースで選択しながら、android, ios, webにチェックをつけてEnter
- 必要なパッケージの導入
  - flutter pub add firebase_core
- 動作確認
  - flutter run -d chrome
## 共同開発では必須ではない手順のメモ
## 更新後のビルド手順
- ビルドは基本hirotakasuzuki1219が実行する
  - `flutter build web`
  - `firebase deploy --only hosting`
### Flutterプロジェクトを新しく立ち上げる
- 作りたい場所にターミナルで移動した後
  - flutter create .
### Firebaseプロジェクトの作成
- 新規でFirebaseプロジェクトを立ち上げたい場合
  - [Firebase Console](https://console.firebase.google.com/u/0/) にアクセス。
  - 「プロジェクトを追加」をクリック（名前は「mori-game」など）。
  - Google Analytics は、将来の分析のためにONにしておくと良いです。