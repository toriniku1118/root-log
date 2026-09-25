# 内部設計(ステップ1:記録と来歴)

- 版:初版(2026-09-26)。issue #22。
- 位置づけ:V字の内部設計。作り方(構成・データ・処理の流れ・エラー処理・保存先の境目)。対応するテストは、結合テスト(`test-plan.md`)。
- 元になった文書:`docs/step0-design.md` の1章(データ設計)、実装の現状(`app/lib/`・`firebase/`)。設計0とこの文書が食い違うときは、この文書を正とし、設計0は履歴として残す。
- 根底は「交流と交換」で、記録はそれを効果的に実現するためのもの(`requirements.md` 0章)。データの設計では、あとから「見せ合う」「交換する」ときに効く情報(来歴・入手先・公開範囲)を、今のうちから失わずに持つ。

## 1. 構成(層と責務)
アプリは `app/lib/` の下を、次の層に分ける。依存は上から下への一方向。

```
features/  画面(Flutter のウィジェット)。保存先の種類(メモリ/Firestore)を知らない
   ↓
providers.dart  依存の組み立て(Riverpod)。保存先の差し替えはここだけ
   ↓
data/      保存先へのアクセス(PlantRepository とその実装)
   ↓
domain/    株・ジャンル・タグ・入力の検証。Flutter や Firebase に依存しない
```

| 場所 | 中身(現状) | 責務 |
|---|---|---|
| `main.dart` / `app.dart` | アプリの起動、日本語設定、テーマ | 全体の設定だけ |
| `constants.dart` | アプリ名(仮) | 定数 |
| `domain/plant.dart` | `Plant`(株)、`PlantVisibility`(共有設定)、`PlantScope`(公開範囲) | 株の形。来歴の印は持たない(サーバーだけが付ける) |
| `domain/plant_genre.dart` | `PlantGenre`(9種類)、`defaultPlantGenre` | ジャンルの id と表示名。id は権限ルールと同じ |
| `domain/plant_tag.dart` | `PlantTag`(復活チャレンジ・実生) | タグの id と表示名。id は権限ルールと同じ |
| `domain/plant_input.dart` | `PlantInput`、`PlantLimits`、`validatePlantInput`、`PlantValidationException` | 入力の正規化と検証。条件は権限ルールと同じ |
| `data/plant_repository.dart` | `PlantRepository`(差し替え口)、`InMemoryPlantRepository`、`generatePlantId`、`PlantNotFoundException` | 株の保存・取得。今はメモリ上 |
| `providers.dart` | `plantRepositoryProvider`、`plantsProvider` | 保存先の提供と、一覧の購読 |
| `features/home/` | `HomeScreen`、`groupPlantsByLocation` | ホーム(SCR-04)と、置き場所ごとのまとめ |
| `features/plants/` | `AddPlantScreen`(仮) | 株を追加する画面(SCR-05。#17 で作る) |

- 新しい機能(記録・写真・設定・通知)も、同じ形で足す:`domain/` に形と検証、`data/` に差し替え口と実装、`features/` に画面、`providers.dart` で結ぶ。
- 画面は、保存先が返す例外([6章](#6-エラー処理))を、日本語のメッセージにして出す。

## 2. 状態管理
- Riverpod(`flutter_riverpod` 3系)を使う。
- `plantRepositoryProvider`:保存先を返す `Provider`。今は `InMemoryPlantRepository`。Firebase 接続後は Firestore 版に差し替える(4章)。テストでは `overrideWithValue` などで、時計と ID の生成を固定した保存先に差し替える。
- `plantsProvider`:株の一覧を流す `StreamProvider`。保存先の `watchAll()` を購読する。購読した時点の内容がすぐ流れ、変更のたびに新しい一覧が流れる。
- 画面の状態(読み込み中・データあり・エラー)は `AsyncValue` の `when` で分けて表示する(ホームの実装どおり)。
- 記録・写真・ユーザー設定も、同じ形で `Provider`(保存先)と `StreamProvider`(購読)を足す。

## 3. データモデル

### 3.1 保存先の構造(Firestore・Cloud Storage)
設計0の1.2〜1.3のとおり。権限ルールは `firebase/firestore.rules`・`firebase/storage.rules`。

| パス | 内容 | アプリから | サーバーから |
|---|---|---|---|
| `users/{uid}` | 表示名・年齢区分・好きなジャンル・都道府県・通知設定(`notify`)・課金状態(`plan`) | 本人が作成・更新(年齢区分・課金状態は不可。削除は不可) | 課金状態を書く。削除は `deleteAccount` |
| `users/{uid}/plants/{plantId}` | 株 | 本人が作成・更新・削除(来歴の印は不可) | 来歴の印(`hasProvenance`)を書く |
| `…/logs/{logId}` | 記録 | 本人が作成・更新・削除(種類・記録時刻は変更不可) | 後片付け |
| `…/photos/{photoId}` | 写真の記録 | 読むだけ | 作成・削除 |
| `…/systemLogs/{id}` | 来歴の欠落など | 読むだけ | 作成 |
| `publicPlants/{uid}_{plantId}`・`publicProfiles/{uid}` | 公開用データ | 読むだけ(ステップ3から) | 書き出し |
| `photoHashes/{sha256}` | 写真の使い回しの検出用 | なし | 読み書き |
| `uploads/{uid}/{uploadId}` | 元画像 | 作成だけ | 処理後すぐ削除 |
| `photos/{uid}/{photoId}.jpg` | 処理済みの写真 | 本人が読む | 書き込み |
| `public/{uid}/{photoId}.jpg` | 公開を選んだ株の写真のコピー | ログイン済みなら読む | 書き込み |

### 3.2 株(`Plant` ↔ `users/{uid}/plants/{plantId}`)
| アプリ(Dart) | Firestore の項目 | 型・条件 | 備考 |
|---|---|---|---|
| `id` | ドキュメント ID | 英数字・`_`・`-`、1〜64文字(写真の受付の条件) | `generatePlantId()` が20文字を作る |
| `name` | `name` | 文字列、1〜50 | 必須 |
| `genre` | `genre` | 9種類のどれか(`foliage` `caudex` `agave` `succulent_cactus` `platycerium` `aroid` `rare` `seedling` `other`) | 必須 |
| `variety` | `variety` | 文字列、〜80 | 任意 |
| `acquiredAt` | `acquiredAt` | タイムスタンプ | 任意。今日以前(アプリで検証。ルールは型だけ) |
| `source` | `source` | 文字列、〜100 | 任意。入手先(非公開。「入手先まで」を公開したときだけ公開用に出る) |
| `locationName` | `locationName` | 文字列、〜30 | 任意。名前だけ。住所は持たない |
| `potSize` | `potSize` | 文字列、〜10 | 任意 |
| `tags` | `tags` | `rescue` / `seedling` の配列、10個まで | 必須 |
| `visibility` | `visibility.public`、`visibility.scope` | 真偽値、`photos` / `history` / `source` | 必須。作成時は `public: false`、`scope: photos` |
| `createdAt` / `updatedAt` | `createdAt` / `updatedAt` | サーバー時刻 | 必須。ルールが `request.time` と一致を要求する |
| (持たない) | `hasProvenance` | 真偽値 | サーバーだけが書く。アプリの `Plant` は持たず、書き戻さない |

### 3.3 これから追加するデータ
| データ | 保存先 | 内容 | 状態 |
|---|---|---|---|
| 記録 `PlantLog` | `…/logs/{logId}` | `type`(`water` `repot` `fertilize` `prune` `note` `stage`)、`occurredAt`(今日以前)、`recordedAt`(サーバー時刻)、`note`(〜500)、`stage`(`acquired` `rooted` `new_leaf` `repotted` `flowered` `divided` `recovered` `died`) | ルールは済み。アプリは未 |
| 写真 `PlantPhoto` | `…/photos/{photoId}` | 保存先、サイズ、撮影元、受信時刻(`receivedAt`)、来歴かどうか(`provenance`)と理由(`provenanceReason`)など | サーバーが作る。アプリは読むだけ |
| ユーザー `UserProfile` | `users/{uid}` | 表示名(1〜30、必須)、年齢区分、好きなジャンル(9個まで)、都道府県(コード `01`〜`47` または空)、通知設定(`notify`) | ルールは済み。アプリは未 |

### 3.4 通知設定(`users.notify`)
- 種類は6つで、値はオン/オフ(真偽値)だけ:`photo`(撮影)、`event`(イベント)、`water`(水やり)、`weather`(季節・天気)、`reaction`(反応)、`stock`(入荷)。
- **初期値はすべてオフ**(2026-09-26 の決定)。ルールは `notify` の存在を必須にしているので、ユーザー情報を作るとき、アプリがすべて `false` で書く。
- ステップ1で使うのは `photo` と `water` だけ。ほかの種類は、それぞれのステップで使う。
- 撮影通知の頻度・時間、株ごとの水やり通知のオン/オフは、`notify` に入れる場所がない。**保存先は未決**(`requirements.md` 6章 Q3)。決めたら、権限ルールを変え、「見えてはいけないものが見えない」テストを追加する(REQ-044)。

## 4. 保存先の差し替え(メモリ → Firestore)

### 4.1 差し替え口
`PlantRepository`(`app/lib/data/plant_repository.dart`)が差し替え口。画面は、保存先がメモリか Firestore かを知らない。

| 操作 | 内容 | 例外 |
|---|---|---|
| `watchAll()` | 株の一覧を流す。購読した時点の内容がすぐ流れ、変更のたびに新しい一覧が流れる | — |
| `add(input)` | 株を追加する。必ず非公開 | 条件を満たさないとき `PlantValidationException`(1件も増えない) |
| `update(id, input)` | 株を更新する。共有設定・作成日時は変えない。更新日時は進む | 存在しないとき `PlantNotFoundException`。条件を満たさないとき `PlantValidationException`(元の内容が残る) |
| `delete(id)` | 株を削除する。存在しなくてもエラーにしない | — |

### 4.2 Firestore 版に必要なこと(権限ルールとの取り決め)
1. **作成**:`visibility.public` は `false`。`hasProvenance` は含めない。`createdAt` と `updatedAt` はサーバー時刻(`FieldValue.serverTimestamp()`)。
2. **更新は `update` か `set(merge)`**:全体を上書きすると、サーバーが付けた `hasProvenance` が消え、ルールに拒否される(`unchanged(['createdAt','hasProvenance'])`)。変えた項目だけを書く。共有設定は、共有設定の画面だけが書く。
3. **項目を空にする**:任意の項目は、書かない(未設定)か `null` のどちらもルールを通る。空欄は `null` にして書く。
4. **文字数**:ルールの `size()` は UTF-16 の単位で数える(絵文字は2文字分)。アプリの `validatePlantInput` も同じ数え方(Dart の `length`)。実測は `firebase/tests/firestore.rules.test.ts` にある。
5. **一覧**:`users/{uid}/plants` の変更を購読して `Plant` の一覧に変換する。`hasProvenance` は、来歴の印の表示(REQ-018)に使う値として、別に読む(`Plant` に持たせるか、表示用の別の型にするかは実装時に決める)。
6. **削除**:株のドキュメントを消すと、`onPlantDeleted` が写真・記録・公開用データを後片付けする。アプリは記録・写真を1件ずつ消さない。
7. **接続先の切り替え**:開発中はエミュレーター(7章)。`plantRepositoryProvider` の中で、Firestore 版に切り替える。画面のコードは変えない。

## 5. 入力検証
- 検証は `validatePlantInput(input, now:)` に一元化する。画面は、その結果(項目ごとの日本語のメッセージ)を出すだけ。
- 条件は権限ルールと同じにする。

| 項目 | 条件 | アプリの上限(`PlantLimits`) | ルール |
|---|---|---|---|
| 名前 | 必須、1〜50文字 | `name = 50` | `isStr(name, 1, 50)` |
| 品種 | 任意、〜80文字 | `variety = 80` | `optStr('variety', 80)` |
| 入手先 | 任意、〜100文字 | `source = 100` | `optStr('source', 100)` |
| 置き場所 | 任意、〜30文字 | `locationName = 30` | `optStr('locationName', 30)` |
| 鉢の号数 | 任意、〜10文字 | `potSize = 10` | `optStr('potSize', 10)` |
| 入手日 | 任意、今日以前 | — | 型(タイムスタンプ)だけ。「今日以前」はアプリだけで検証 |
| ジャンル | 9種類のどれか | `PlantGenre` の id | `genres()` |
| タグ | `rescue` / `seedling` | `PlantTag` の id | `tags.hasOnly([...])` |

- 前後の空白は取り除き、空欄は「未設定」(`null`)にする(`PlantInput.normalized()`)。
- **一致の見張り**:`test/domain/plant_rules_consistency_test.dart` が、`firebase/firestore.rules` の文字列を読み、ジャンル・タグ・公開範囲の id、文字数の上限、「新規作成は非公開を強制」「来歴の印はサーバー専用」がアプリと同じかを確かめる。ルールかアプリのどちらかを変えたら、このテストが落ちる。
- 記録(`PlantLog`)にも同じ形で、`validatePlantLog`(メモ〜500文字、日時は今日以前、種類・段階は決めた値)を足す。

## 6. エラー処理
| 起きること | 例外・状態 | 画面での扱い |
|---|---|---|
| 入力が条件を満たさない | `PlantValidationException`(項目とメッセージ) | 項目のそばに日本語のメッセージ。保存しない |
| 更新しようとした株がない | `PlantNotFoundException` | 「株が見つかりません」を出し、ホームへ戻る |
| 一覧を読み込めない | `AsyncValue` のエラー | 「株を読み込めませんでした」 |
| 読み込み中 | `AsyncValue` の読み込み中 | 進行中の表示 |
| 権限ルールで拒否された(Firestore 版) | Firestore の権限エラー | 「保存できませんでした。もう一度試してください」。原因はログに残す(内部の詳細を利用者に見せない) |
| 通信の失敗 | 通信エラー | 「もう一度試してください」。入力は消さない |
| 写真のアップロード失敗 | アップロードのエラー | 「写真を送れませんでした」。端末に残し、再試行できる形にする(8章) |
- 例外を握りつぶさない。画面に出す文言は日本語で、専門用語を避ける。
- サーバー処理の失敗は、Cloud Functions のログに残し、来歴を「作れなかった」ことがアプリから分かるようにする(8章)。

## 7. Firebase 接続の計画
1. **プロジェクト**:開発用・本番用の2つ(REQ-041)。`flutterfire configure` で設定する。`google-services.json`・`GoogleService-Info.plist` はコミットしない(REQ-043)。
2. **エミュレーター**:`docker compose up firebase`(Firestore・Storage・Functions)で、ローカルで先に確かめる。ローカルで一通り動いてから、開発用プロジェクトにつなぐ。
3. **サインイン**:Firebase Authentication で Apple / Google。サインインの実際の動きは実機で確認する(P3)。**接続前は仮のユーザー**(固定の uid)でメモリ上の保存先を動かし、全画面をつなぐ(P1)。仮のユーザーの扱いは未決(`requirements.md` Q8)。
4. **ユーザー情報の作成**:サインイン後、年齢区分・好きなジャンル・通知設定(すべてオフ)・表示名・都道府県で `users/{uid}` を作る。表示名(必須)と都道府県を、どの画面で決めるかは未決(Q1・Q2)。
5. **App Check**:有効にする(REQ-039)。`deletePhoto`・`deleteAccount` は App Check を必須にしてある。
6. **Analytics**:ステップ1では、判定に使う数字を記録のデータから数える(`test-plan.md` 5章)。Analytics の利用は、同意とプライバシー表示(セキュリティ 9章)を決めてから。
7. **Storage のバケット**は東京(`asia-northeast1`)に作る(Storage のトリガーと同じリージョンにするため)。

## 8. 写真の流れ
設計0の1.4のとおり。アプリ側の受け持ちは次のとおり。
1. 撮影(アプリ内カメラ)→ すぐ `uploads/{uid}/{uploadId}` に保存。メタデータに `plantId` と `source`(`camera` / `gallery`)を必ず付ける(付けないと、ルールが拒否する)。
2. 保存に失敗したら、端末に写真を残し、再試行できる形にする(通信が切れたときに、撮影が無駄にならないため)。
3. サーバー(`processUpload`)が、メタデータの削除・縮小・来歴の判定・写真の記録の作成・元画像の削除を行う。数秒後に、`…/photos/{photoId}` ができる。
4. アプリは、株の写真の一覧を購読する。写真の記録ができるまでは「確認中」と表示する。できたら、`provenance` と `provenanceReason` から、外部設計 3.7.1 の表示を出す。
5. サーバーが来歴を作れなかった(画像の形式が違う・大きすぎる・株がない、など)ときは、写真の記録ができない。一定時間たっても記録ができなければ「確認できませんでした」と表示し、もう一度撮影できるようにする。
6. 写真の削除は、`deletePhoto`(App Check 必須)を呼ぶ。アプリから `photos` を直接消さない(ルールが拒否する)。

## 9. 通知
- 通知は**オプトイン**。ユーザー情報の作成時にすべて `false`。オンにした種類だけ動かす(REQ-030〜032)。
- 撮影通知・水やり通知は、端末のローカル通知として予約する案(サーバーからの送信は使わない)。実装するときに、ローカル通知のライブラリを選び、設計を更新する。
- 通知は全種類あわせて原則1日1回まで。同じ日に重なったときは、優先順位(反応 → 天気の警報 → 撮影・水やり → その他)で1つにまとめる。ステップ1で実際に動くのは撮影と水やりだけなので、この2つで重ならないようにする(同じ日は撮影通知に水やりをまとめる)。
- 通知の許可(OS のダイアログ)は、SCR-10で「知らせる」を選んだときだけ出す。
- 実際の通知の動きは、実機で確認する(P3)。

## 10. サーバー処理(Cloud Functions 第2世代・東京)
| 処理 | きっかけ | 内容 | アプリから見ると |
|---|---|---|---|
| `processUpload` | `uploads/` への保存 | 画像の形式の確認(JPEG/PNG、4,000万画素まで)・メタデータの削除・縮小(無料1600px・有料3000px)・来歴の判定・写真の記録の作成・元画像の削除。1インスタンスで1枚ずつ | 写真の記録が数秒後にできる |
| `deletePhoto` | アプリからの呼び出し(App Check 必須) | 写真と公開コピーの削除、`systemLogs` に来歴の欠落を記録 | 写真を消す |
| `onPlantDeleted` | 株の削除 | 写真・記録・公開用データの後片付け | 株を消すと、関連も消える |
| `onPlantWritten` / `onPlantLogWritten` | 株・記録の作成・更新 | 公開を選んだ株だけ、選んだ範囲を `publicPlants` に書き出す。非公開に戻したら、公開用データと写真のコピーを削除 | (ステップ3まで、アプリは参照しない) |
| `deleteAccount` | アプリからの呼び出し(App Check 必須) | 公開用データ・写真・記録・ログイン情報をすべて削除 | アカウントを消す |

- 来歴の判定の定数(`firebase/functions/src/index.ts`):撮影時刻と受信時刻の差は10分以内(`PROVENANCE_MAX_DELAY_MS`)。タイムゾーン情報がない場合は1時間単位のずれ(-14〜+14時間)を許容する。画質は無料 `FREE_LONG_EDGE = 1600`、有料 `PREMIUM_LONG_EDGE = 3000`(`plan == 'premium'` のとき)。
- 来歴の理由(`provenanceReason`):`ok` `gallery` `no_capture_time` `capture_time_mismatch` `duplicate`。
- 限界(設計0の1.4):撮影元と撮影時刻は端末側の情報で、改造したアプリなら偽装できる。確実なのはサーバーの受信時刻だけ。別の株を撮って来歴にすることも防げない。画面は「この日時までに撮影された写真」と表示する。

## 11. 実装の現状との突き合わせ(2026-09-26)
設計書と実装(`app/lib/`・`firebase/`)を突き合わせた結果。食い違い・確認事項は、次のとおり。

| # | 確認したこと | 結果 | 対応 |
|---|---|---|---|
| 1 | ジャンルの id・表示名(9種) | 一致(`plant_genre_test.dart`、`plant_rules_consistency_test.dart`) | なし |
| 2 | タグ・公開範囲の id | 一致 | なし |
| 3 | 文字数の上限(名前50・品種80・入手先100・置き場所30・号数10) | 一致(`PlantLimits` とルール) | なし |
| 4 | 新規作成は必ず非公開、来歴の印はアプリから持たない | 一致 | なし |
| 5 | ホームの機能 | 一覧・置き場所のまとめ・0件の案内・「株を追加」まで。「巡回する」・設定への入口・最新写真・前回の撮影からの日数・来歴の印は未 | 外部設計 3.5 に「現状」として明記。要件 REQ-005 は「一部」 |
| 6 | 株を追加する画面 | 「準備中」の仮(#17 で作る) | 外部設計 SCR-05 に明記 |
| 7 | 配色の指定 | `app.dart` で `colorSchemeSeed: Colors.green` とダークテーマを指定。開発ルールは「テーマは既定のまま」 | 見た目を作り込む段階(別の作業)で扱う。今は変えない。ワイヤーフレーム方針とのずれとして記録 |
| 8 | `users.displayName`(必須)を入力する画面 | 設計0の画面一覧にない | 未決 Q1 |
| 9 | `users.prefecture` を入力する画面 | 設計0の画面一覧にない(空でも保存できる) | 未決 Q2 |
| 10 | 撮影通知の頻度・時間の保存先 | `users.notify` に入れる項目がない | 未決 Q3 |
| 11 | 通知の初期値 | ルールは `notify` の存在を要求し、初期値の決まりはない | アプリが作成時にすべて `false` で書く(3.4) |
| 12 | 対応する OS | Android のみ作成済み(iOS は未) | REQ-042 は「一部」 |
| 13 | Firebase | 未設定(アプリはメモリ上の保存先だけ) | REQ-041 は「未」 |
| 14 | 設計0の画面「株を追加」 | この設計書では「株を追加・編集」に広げた(同じ入力項目) | 外部設計 1章に明記 |
| 15 | 設計0の作業順 | 「Flutter を先に、Firebase は後」とは書かれていない | 要件 3章で、開発ルールの方針(全画面をつなぐのが先)に合わせて順序を決めた |
| 16 | 根底(交流と交換) | ステップ1には交流・交換の機能がない | 要件 0章・未決 Q9 |
