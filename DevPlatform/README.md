# DevPlatform 配布キット

このフォルダは、Windows Sandbox を使った開発環境の「定義配布」用です。

- ベースパス: 任意（どこに置いても可）
- 標準起動: `start-sandbox.cmd` または `start-sandbox.ps1`
- Sandbox メモリ: `MemoryInMB=16384` (16GB)

## フォルダ構成

```text
DevPlatform/
  start-sandbox.cmd
  start-sandbox.ps1
  sandbox/
    wsb/
      dev-online-16gb.wsb
      dev-online-16gb.generated.wsb (起動時に自動生成)
    scripts/
      bootstrap.ps1
      setup-vscode.ps1
      verify.ps1
      export-mark2-reg.ps1
    config/
      env.lock.json
      extra-mapped-folders.json
      extra-mapped-folders.sample.json
      mark2-bootstrap.reg
    logs/
  projects/
  hyperv/
    templates/
    exports/
    backups/
```

## 使い方

1. `start-sandbox.cmd` をダブルクリックして起動
2. スクリプトが現在位置から実パスを解決し、`dev-online-16gb.generated.wsb` を生成
3. 生成された `.wsb` で Sandbox を起動
4. 起動後に `bootstrap.ps1` が自動実行される
5. `env.lock.json` の定義に従ってツールを導入
6. `verify.ps1` が `sandbox\logs` に検証ログを出力
7. 作業は `projects` 配下で実施

補足:
- `dev-online-16gb.wsb` は固定パス版（互換用）です
- 移設後は `start-sandbox.cmd` 経由で起動してください
- これにより、配置場所が変わっても起動できます

旧手順:
- `dev-online-16gb.wsb` のダブルクリック直起動は、パス移動後に `0x80070002` になりやすい

## `projects` と自社アプリ保管庫の使い分け

- `projects`: 開発中のソースコードを置く場所（書き込み前提）
- 自社アプリ保管庫（例: `C:\Mark2`）: 実行バイナリや共通資材を置く場所（原則読み取り専用）

推奨:
- ソースは `projects` のみ
- 共通ツール/社内アプリは `extra-mapped-folders.json` で `C:\<AppName>` にマウント

`sandbox\config\extra-mapped-folders.json` 例:

```json
[
  {
    "HostFolder": "C:\\Mark2",
    "SandboxFolder": "C:\\Mark2",
    "ReadOnly": false
  }
]
```

メモ:
- `HostFolder` が存在しないと起動時にエラーで停止します
- 書き込みが必要な場合のみ `ReadOnly: false` を使います

## Mark2 レジストリ初期状態の反映（HKCU）

対象キー:
- `HKEY_CURRENT_USER\Software\System-I\Mark2`

手順:
1. ホストで現在の設定をエクスポート  
   `powershell -ExecutionPolicy Bypass -File .\sandbox\scripts\export-mark2-reg.ps1`
2. `sandbox\config\mark2-bootstrap.reg` が更新される
3. `start-sandbox.cmd` で起動
4. 起動時に `bootstrap.ps1` が `C:\Config\mark2-bootstrap.reg` を `reg import` する

注意:
- Sandbox内で変更した HKCU は終了時に破棄されます
- 次回以降にも反映したい変更は、ホスト側で再エクスポートしてください

## トラブル時の確認

- `sandbox\logs\bootstrap-*.log`: 起動時セットアップの詳細ログ
- `sandbox\logs\verify-*.log`: git/code/python/node の検証結果
- `sandbox\config\mark2-bootstrap.reg`: 空のテンプレートではなく、実際に export された内容かを確認

## メモリ/容量指定について

### メモリ

- 指定可: `<MemoryInMB>16384</MemoryInMB>`
- Sandbox はホスト状態により実使用量が動的に変動する

### 容量

- `.wsb` で「Sandbox仮想ディスク容量」を直接固定する項目はない
- 容量制御は実務上、次で行う:
  - `projects` など保存先を限定する
  - `logs` をローテーションする
  - 重いキャッシュはホスト側で管理する

## `.wsb` で指定できる主な項目

- `vGPU`: 仮想GPUの有効/無効
- `Networking`: ネットワーク有効/無効
- `MemoryInMB`: メモリ上限の指定
- `MappedFolders`: ホストフォルダのマウント
- `LogonCommand`: 起動時コマンド
- `ClipboardRedirection`: クリップボード連携
- `AudioInput`: 音声入力デバイス連携
- `VideoInput`: カメラ入力デバイス連携
- `PrinterRedirection`: プリンタ連携
- `ProtectedClient`: 保護モード

## 更新ルール

- ツール版は `sandbox\config\env.lock.json` を更新
- スクリプト修正は `sandbox\scripts` に反映
- 変更後は `verify` ログで結果確認

## Hyper-V 用途（例外）

`hyperv` 配下は、GPU必須処理や長時間ジョブ向けのテンプレート/バックアップ用です。

- `templates`: テンプレートVM管理
- `exports`: エクスポート保存先
- `backups`: バックアップ格納先
