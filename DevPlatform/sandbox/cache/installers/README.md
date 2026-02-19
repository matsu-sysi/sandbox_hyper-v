# installers 運用README

このフォルダは、Sandbox起動時に使う「ローカルインストーラ置き場」です。  
`bootstrap.ps1` は `C:\Installers`（このフォルダのマウント先）からインストーラを参照します。

## ここに置くもの

- `env.lock.json` の `installerFile` と一致するファイル
- 例:
  - `VSCodeUserSetup-x64-latest.exe`
  - `Git-2.53.0-64-bit.exe`
  - `python-3.13.12-amd64.exe`
  - `node-v24.13.1-x64.msi`

## 置かないもの

- ソースコード
- プロジェクト成果物
- Sandbox実行ログ

## 更新方法

1. 以下を実行してインストーラを更新
   - `powershell -ExecutionPolicy Bypass -File .\sandbox\scripts\update-installers.ps1`
2. `sandbox\config\env.lock.json` の `installerFile` / `version` を必要に応じて更新
3. `start-sandbox.cmd` で起動し、`sandbox\logs\verify-*.log` を確認

## 運用ルール

- 起動失敗を避けるため、`installerFile` 名は `env.lock.json` と必ず一致させる
- 大容量バイナリは Git 管理しない（`.gitignore` で除外）
- `installers.manifest.json` は Git 共有し、取得元URL/ハッシュの確認に使う

## トラブル時

- `Local installer not found` が出た場合:
  - `env.lock.json` の `installerFile` と実ファイル名を照合
  - `update-installers.ps1` を再実行
