# 開発ルール

RootLog の開発の進め方。`CLAUDE.md` の「開発の進め方」の詳細版。人も Claude Code も同じ流れで進める。

## 全体の流れ
要件と仕様を決める → issue を作る → worktree を作る → 実装・テスト → PR を作る → マージ → ブランチと worktree を削除

## 1. 要件と仕様を先に決める
作業を始める前に、issue の本文に次の項目を書く(テンプレート:`.github/ISSUE_TEMPLATE/dev-item.md`)。
- **要件**:なぜ必要か。何ができるようになれば良いか。
- **仕様**:どういう動きにするか。画面・データ・権限など、決めたことを具体的に書く。
- **完了の条件**:何ができたら終わりか。確認方法(テスト・実機での確認など)。
- **セキュリティへの影響**:権限ルール・公開データ・写真・個人情報に関わるか。関わる場合は `docs/project/security-requirements.md` のどの項目か。

決まっていないことがあれば、作業を止めて先に決める(ユーザーに確認する)。仕様が途中で変わったら、issue の本文を更新してから実装を直す。

## 2. issue と sub-issue
- 開発項目は必ず issue にする。issue がない作業はしない。
- 大きい項目は親 issue にして、ステップ1の画面ごと・機能ごとなどに分けた sub-issue をぶら下げる。
  - 親 issue:目的と全体の完了条件を書く。
  - sub-issue:1つが「1つの PR で終わる大きさ」になるように分ける。
- sub-issue は GitHub の sub-issue 機能で親に紐づける(紐づけできない場合は、親 issue の本文にチェックリストで `- [ ] #番号` と書く)。
- ラベルの目安:`step1` 〜 `step6`(開発ステップ)、`security`、`docs`、`bug`。

## 3. worktree とブランチ
- 作業は必ず worktree で行う。`main` の作業ディレクトリでは編集しない。
- worktree は `.claude/worktrees/` 以下に作る(Git に含めない)。
- ブランチ名:`<種類>/<issue番号>-<英数字の短い説明>` 例)`feat/12-plant-list`、`docs/3-dev-rules`。種類は `feat` / `fix` / `docs` / `chore`。
- 1つの worktree・ブランチ・PR は、1つの issue(または sub-issue)に対応させる。
- Docker は、どの worktree からでも同じイメージ・キャッシュ・adb の認証キーを使う(`docker-compose.yml` で `name: rootlog` に固定)。ただし `node_modules` も共有されるので、ブランチで `package-lock.json` が変わったら `npm ci` で合わせる。
- 作業が終わった worktree に、ディレクトリ名付きの Docker イメージやボリュームが残っていたら削除する。

## 4. PR とマージ
- PR の本文に、`Closes #issue番号`、変更の概要、確認したこと(テスト結果など)を書く(テンプレート:`.github/pull_request_template.md`)。
- **マージの承認は不要**。次を確認できたら、自分でマージしてよい。
  - `firebase/` を変えた場合:`npm test` と型チェックが全件合格している。
  - 権限ルールを変えた場合:「見えてはいけないものが見えない」テストを追加してある。
  - 秘密情報(APIキー・秘密鍵・`google-services.json`・`GoogleService-Info.plist`)が含まれていない。
- マージ方法は squash マージ(`gh pr merge --squash --delete-branch`)。履歴を1 issue = 1 コミットにそろえる。
- 確認で失敗した場合はマージせず、直してから再確認する。

## 5. マージ後の片付け
- リモートのブランチを削除する(`--delete-branch`)。GitHub のリポジトリ設定「Automatically delete head branches」も有効にしておく。
- ローカルのブランチと worktree を削除する(`git worktree remove <パス>` と `git branch -D <ブランチ>`。squash マージ後は `-d` が使えないため)。
- `main` を最新にする(`git pull`)。
- issue が閉じていることを確認する。sub-issue がすべて閉じたら、親 issue も閉じる。

## 使うコマンドの例
```bash
gh issue create --title "..." --body-file issue.md
gh issue develop <番号> --name <ブランチ名>          # 任意。ブランチ名を issue に紐づける
git worktree add .claude/worktrees/<名前> -b <ブランチ名> origin/main
gh pr create --title "..." --body "Closes #<番号> ..."
gh pr merge --squash --delete-branch
git worktree remove .claude/worktrees/<名前> && git branch -D <ブランチ名>
```
