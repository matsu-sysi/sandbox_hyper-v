# DevPlatform 配布キット

Windows Sandbox 用の定義配布キットです。  
方針は「ローカルインストーラ優先」「ネット fallback 最小」です。

## 起動

1. `start-sandbox.cmd` を実行
2. `start-sandbox.ps1` が実パス解決して `sandbox\wsb\dev-online-16gb.generated.wsb` を生成
3. `session.json` に起動ID/ログパスを書き込み
4. Sandbox 起動後に `C:\Bootstrap\bootstrap.ps1` が自動実行

注記:
- `start-sandbox.cmd` は既定で `-ForceRestart` を付与して起動します（残留セッション自動整理）

残留セッションがある場合:

```powershell
.\start-sandbox.cmd -ForceRestart
```

## フォルダ構成

```text
DevPlatform/
  start-sandbox.cmd
  start-sandbox.ps1
  sandbox/
    cache/
      installers/
        installers.manifest.json
    config/
      env.lock.json
      extra-mapped-folders.json
      host-tools.json
      mark2-bootstrap.reg
    logs/
    scripts/
      bootstrap.ps1
      verify.ps1
      export-mark2-reg.ps1
      update-installers.ps1
    wsb/
      dev-online-16gb.wsb
      dev-online-16gb.generated.wsb
  projects/
  hyperv/
```

## 現在の実装ルール

- 16GB メモリ: `MemoryInMB=16384`
- `projects` は RW マウント（ソース保管）
- `sandbox\cache\installers` は RO マウントで `C:\Installers`
- アプリ追加マウントは `extra-mapped-folders.json`
- ホスト既存ツールの参照は `host-tools.json`（任意）
- ログは `YYYY-MM-DD\run-<起動ID>.log` に1起動1ファイルで集約

## ツール導入フロー（bootstrap）

1. `mark2-bootstrap.reg` を import（存在時）
2. `env.lock.json` を読み込み
3. 既にコマンドが見えるパッケージは skip
4. 未導入分を `C:\Installers\<installerFile>` から silent install
5. `useWingetFallback=true` の場合のみ winget fallback
6. `verify.ps1` で `git/code/python/node` をログ出力

注記:
- `env.lock.json` の `autoInstall=false` は起動時に自動導入しません
- 現在は安定性優先で `Python/Node` を `autoInstall=false` にしています

## インストーラ更新

次で最新安定版を取得して `sandbox\cache\installers` を更新します。

```powershell
powershell -ExecutionPolicy Bypass -File .\sandbox\scripts\update-installers.ps1
```

取得結果は `installers.manifest.json` に記録されます。

## Mark2 レジストリ初期化

対象: `HKCU\Software\System-I\Mark2`

```powershell
powershell -ExecutionPolicy Bypass -File .\sandbox\scripts\export-mark2-reg.ps1
```

出力先: `sandbox\config\mark2-bootstrap.reg`  
Sandbox 起動時に自動 import されます。

補足:
- `mark2-bootstrap.reg` は機微情報を含むため Git 追跡対象外
- 共有用テンプレートは `sandbox\config\mark2-bootstrap.sample.reg`

## ログ

- 形式: `sandbox\logs\YYYY-MM-DD\run-<起動ID>.log`
- 1回の起動につき1ファイルを作成し、以下を同じファイルへ追記
  - `start-sandbox.cmd` の起動情報
  - `start-sandbox.ps1` のランチャー処理
  - `bootstrap.ps1` のセットアップ処理
  - `verify.ps1` の検証結果

## 失敗時の確認順

1. 最新の `sandbox\logs\YYYY-MM-DD\run-<起動ID>.log` を開く
2. `Required path(s) missing` があるか確認
3. `Windows Sandbox is still running` があるか確認
4. `Local installer not found` / `Installer exit code` / `Installer timed out` を確認
5. `VERIFY` ブロックで `MISSING` のコマンドを確認

## VS Code 拡張

- 拡張一覧は `sandbox\config\env.lock.json` の `vscodeExtensions` で管理
- 起動時に `code --install-extension` で適用
- 失敗時はログに警告を残し、処理継続

## 参考URL

- Windows Sandbox 設定 (`.wsb`)
  - https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-configure-using-wsb-file
- Windows Sandbox サンプル構成
  - https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-sample-configuration
- Windows Sandbox FAQ
  - https://learn.microsoft.com/en-us/windows/security/application-security/application-isolation/windows-sandbox/windows-sandbox-faq
- VS Code Portable mode
  - https://code.visualstudio.com/docs/editor/portable
- VS Code Enterprise Extensions
  - https://code.visualstudio.com/docs/enterprise/extensions
- winget export/import
  - https://learn.microsoft.com/en-us/windows/package-manager/winget/export
  - https://learn.microsoft.com/en-us/windows/package-manager/winget/import
- 参考記事（確認済み）
  - https://dev.classmethod.jp/articles/vscode-preinstalled-windows-sandbox/
  - https://lang-ship.com/blog/work/windows-sandbox/

## Git管理

`.gitignore` で以下を除外済み:

- `sandbox/logs/*`
- `sandbox/wsb/*.generated.wsb`
- `sandbox/cache/installers/*`（`README.md` / `installers.manifest.json` は追跡）
- `sandbox/config/mark2-bootstrap.reg`（実データ）
