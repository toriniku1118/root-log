# RootLog(仮名)ステップ0 成果物

植物の成長記録と「株の来歴」を残すアプリ RootLog のステップ0(準備)の成果物です。

## 中身
| パス | 内容 |
|---|---|
| `docs/step0-design.md` | データ設計、来歴写真の仕組み、サーバー処理、ステップ1の画面設計と作業順 |
| `docs/privacy-policy-draft.md` | テスト版のプライバシーポリシー草案 |
| `docs/terms-draft.md` | テスト版の利用規約草案 |
| `firebase/firestore.rules` | Firestore の権限ルール(デフォルト拒否) |
| `firebase/storage.rules` | Cloud Storage の権限ルール(デフォルト拒否) |
| `firebase/tests/` | 権限ルールの自動テスト(Firestore 43件、Storage 14件) |
| `firebase/functions/src/index.ts` | サーバー処理(写真のメタデータ削除・来歴判定、写真の削除、植物削除の後片付け、公開用データの書き出し、アカウント削除) |

## 権限ルールのテストの実行
前提:Node.js 20以上、Java 11以上。

```bash
cd firebase
npm install
npm test        # Firestore と Storage のエミュレーターを起動してテストを実行
```

## サーバー処理の型チェック
```bash
cd firebase/functions
npm install
npm run build
```

## 注意
- このコードは作成環境の制約でテスト・ビルドを実行できていません。最初に上の2つを実行し、失敗があれば修正してください。
- 規約・ポリシーは草案です。ストア公開前に専門家の確認を受けてください。
- APIキーや秘密鍵はリポジトリに含めないでください(`.gitignore` 参照)。

## 開発環境(Ubuntu PC + Docker)
| やること | 方法 |
|---|---|
| Android 版の開発 | `docker compose run --rm flutter` でコンテナに入り、USB でつないだ Android 実機に `flutter run`(ホットリロード可) |
| Firebase エミュレーター | `docker compose up firebase`(管理画面:http://localhost:4000)。実機からは PC の IP アドレスで接続 |
| 権限ルールのテスト | `docker compose run --rm firebase bash -c "npm install && npm test"` |
| iOS 版のビルド | Linux ではできないため Codemagic(macOS のクラウドビルド、個人は月500分無料)で。`v0.1.0` のようなタグを push すると TestFlight に届く(`codemagic.yaml`) |

注意:
- ホストで adb が動いているとコンテナの adb と取り合いになるため、ホスト側は `adb kill-server` しておく。
- Android エミュレーターを使う場合は、ホスト側で Android Studio のエミュレーターを起動し、コンテナから `adb connect` するより実機の方が簡単で速い。
- `GoogleService-Info.plist` / `google-services.json` はリポジトリに入れない(Codemagic の環境変数で渡す)。
- Dockerfile・compose・codemagic.yaml は作成環境で動作確認できていない。初回のビルドでエラーが出たら調整する。
