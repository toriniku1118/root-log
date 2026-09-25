# Android 実機をつなぐ手順(Windows + WSL2 + Docker)

開発PCが Windows(WSL2)のときに、USB でつないだ Android 実機を Flutter のコンテナ(`docker compose run --rm flutter`)から使う手順。動作確認した実機:Pixel 6a(Android 16)。

## 初回だけ
1. **Windows**(PowerShell を管理者で実行):`winget install usbipd`
2. **スマホ**:「設定 → デバイス情報 → ビルド番号」を7回タップして開発者向けオプションを出し、「USB デバッグ」を ON にする。

## 接続するたびに(WSL を起動し直したとき・USB を抜き差ししたとき)
1. **Windows**(管理者の PowerShell):
   ```powershell
   usbipd list                              # スマホの BUSID を確認(例:2-6)
   usbipd bind --busid <BUSID>              # 抜き差しすると外れることがあるので、そのたびに実行してよい
   usbipd attach --wsl --busid <BUSID>
   ```
2. **WSL**:
   ```bash
   sudo modprobe vhci-hcd                   # WSL を起動し直したあとに1回
   lsusb | grep -i google                   # Bus と Device の番号を確認(抜き差しで Device 番号が変わる)
   sudo chmod 666 /dev/bus/usb/<Bus>/<Device>
   ```
   `chmod` が必要な理由:WSL には udev が動いていないため、デバイスのファイルが root しか読めない状態で作られ、コンテナ内の一般ユーザー(dev)から見えない。
3. **スマホ**:初回は「USB デバッグを許可しますか」が出るので「許可」(「常に許可」にチェックすると次回から出ない)。アプリの起動を画面で確かめるときは、画面のロックを解除しておく。
4. **確認**:
   ```bash
   docker compose run --rm flutter adb devices
   ```
   `device` と表示されれば成功。`unauthorized` はスマホ側で許可が必要。

## ビルドと実機での起動(`app/` のアプリ ID は `com.example.rootlog`)
```bash
docker compose run --rm flutter flutter build apk --debug
docker compose run --rm flutter bash -c "adb install -r build/app/outputs/flutter-apk/app-debug.apk && adb shell am start -n com.example.rootlog/.MainActivity"
```
- デバッグ版の APK は約140MB。USB/IP 経由だと転送に数分かかる。
- ホットリロードで開発するときは `docker compose run --rm flutter flutter run`(終了するまで動き続ける)。
- コンテナの作業ディレクトリは最初から `/workspace/app`。

## うまくいかないとき
| 症状 | 原因と対処 |
|---|---|
| `adb devices` に何も出ない | `lsusb` で `charging + debug` などと出るか確認。`MTP` だけならスマホの USB デバッグが OFF。デバイスのファイル権限(上の `chmod`)も確認 |
| 抜き差ししたら WSL から消えた | Windows 側で `bind` と `attach` をやり直す(`chmod` も) |
| `unauthorized` | スマホの許可ダイアログで「許可」 |
| 起動したのに画面が真っ暗 | スマホがロックされている。ロックを解除する |
| `app/` に書き込めない | コンテナ内の root で所有者を直す:`docker compose run --rm --user root flutter chown -R 1000:1000 /workspace/app` |
| Windows 側の adb と取り合いになる | Windows 側で `adb kill-server` |
