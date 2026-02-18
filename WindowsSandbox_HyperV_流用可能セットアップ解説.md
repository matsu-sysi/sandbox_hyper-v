# Windows Sandbox / Hyper-V 実装運用ガイド（通信必須開発・再現性重視）

最終更新: 2026-02-18  
対象: Windows 11/10 Pro・Enterprise・Education

---

## 1. この文書の前提とゴール

この文書は、次の課題を前提にした実装ガイドです。

- Hyper-V VM の容量が大きく、複製/バックアップコストが高い
- スナップショット運用が難しく、複数人での再利用が破綻しやすい
- 同一環境で開発したいが、環境配布の仕組みが弱い
- ネット通信を前提に開発したい
- GPUが必要な処理は一部で存在する

ゴールは、以下の2つを同時に達成することです。

- 日常開発は軽量な Sandbox で回す
- 例外要件（GPU/長期保持）だけ Hyper-V で吸収する

---

## 2. 方針（結論）

運用の主軸は Windows Sandbox に置きます。  
Hyper-V は「GPU必須」「長時間処理」「永続状態が必要」のときだけ使います。

理由:

- Sandbox は環境定義を配布すれば同一環境を短時間で再現できる
- VMイメージ配布よりストレージコストが大幅に小さい
- 破棄前提なので環境ドリフトが起きにくい
- Hyper-V を常用すると、容量と運用ルールの複雑さが先に限界を迎える

---

## 3. 実装アーキテクチャ

「環境を配る」のではなく「環境定義を配る」構成にします。

```text
C:\DevPlatform\
  ├─ sandbox\
  │   ├─ wsb\
  │   │   └─ dev-online.wsb
  │   ├─ scripts\
  │   │   ├─ bootstrap.ps1
  │   │   ├─ setup-vscode.ps1
  │   │   └─ verify.ps1
  │   ├─ config\
  │   │   └─ env.lock.json
  │   └─ logs\
  ├─ projects\
  └─ hyperv\
      ├─ exports\
      ├─ templates\
      └─ backups\
```

設計意図:

- `sandbox/wsb`: 起動仕様
- `sandbox/scripts`: 起動時処理（セットアップ/検証）
- `sandbox/config`: ツールバージョン固定
- `sandbox/logs`: 構築結果の証跡
- `projects`: 成果物保存（永続）
- `hyperv/*`: 例外用途のVM管理領域

---

## 4. Sandbox 実装（通信必須・VS Code込み）

### 4.1 `.wsb`（標準起動プロファイル）

`C:\DevPlatform\sandbox\wsb\dev-online.wsb`

```xml
<Configuration>
  <vGPU>Enable</vGPU>
  <Networking>Enable</Networking>
  <ClipboardRedirection>Enable</ClipboardRedirection>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>C:\DevPlatform\sandbox\scripts</HostFolder>
      <SandboxFolder>C:\Bootstrap</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>C:\DevPlatform\sandbox\config</HostFolder>
      <SandboxFolder>C:\Config</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>C:\DevPlatform\sandbox\logs</HostFolder>
      <SandboxFolder>C:\Logs</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
    <MappedFolder>
      <HostFolder>C:\DevPlatform\projects</HostFolder>
      <SandboxFolder>C:\Projects</SandboxFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <MemoryInMB>8192</MemoryInMB>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -File C:\Bootstrap\bootstrap.ps1</Command>
  </LogonCommand>
</Configuration>
```

### 4.2 環境固定ファイル

`C:\DevPlatform\sandbox\config\env.lock.json`

```json
{
  "packages": [
    { "id": "Git.Git", "version": "2.48.1" },
    { "id": "Microsoft.VisualStudioCode", "version": "1.98.0" },
    { "id": "Python.Python.3.12", "version": "3.12.9" },
    { "id": "OpenJS.NodeJS.LTS", "version": "22.14.0" }
  ],
  "vscodeExtensions": [
    "ms-python.python",
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint"
  ]
}
```

### 4.3 起動スクリプト（セットアップ本体）

`C:\DevPlatform\sandbox\scripts\bootstrap.ps1`

```powershell
$ErrorActionPreference = 'Stop'

Write-Host '== Network check ==' -ForegroundColor Cyan
Resolve-DnsName github.com | Out-Null
Test-NetConnection github.com -Port 443 | Out-Null

$lock = Get-Content C:\Config\env.lock.json -Raw | ConvertFrom-Json

foreach ($pkg in $lock.packages) {
  winget install --id $pkg.id --version $pkg.version -e `
    --accept-source-agreements --accept-package-agreements
}

& C:\Bootstrap\setup-vscode.ps1 -ExtensionIds $lock.vscodeExtensions
& C:\Bootstrap\verify.ps1

Start-Process explorer.exe C:\Projects
```

`C:\DevPlatform\sandbox\scripts\setup-vscode.ps1`

```powershell
param(
  [Parameter(Mandatory = $true)]
  [string[]]$ExtensionIds
)

foreach ($ext in $ExtensionIds) {
  code --install-extension $ext --force
}
```

`C:\DevPlatform\sandbox\scripts\verify.ps1`

```powershell
$ts = Get-Date -Format yyyyMMdd-HHmmss
$logFile = "C:\Logs\verify-$ts.log"

$lines = @()
$lines += "git: $(git --version)"
$lines += "code: $((code --version | Select-Object -First 1))"
$lines += "python: $(python --version)"
$lines += "node: $(node --version)"
$lines += "date: $(Get-Date -Format o)"

$lines | Out-File -FilePath $logFile -Encoding utf8
```

---

## 5. Sandbox 運用フロー（実務）

### 5.1 初回セットアップ（管理者）

1. Windows 機能で `Windows Sandbox` を有効化  
2. `C:\DevPlatform\` を作成し、上記構成を配置  
3. `env.lock.json` にチーム標準バージョンを定義  
4. `dev-online.wsb` 起動でセットアップ動作を確認

### 5.2 日次運用（開発者）

1. `dev-online.wsb` を起動  
2. 自動セットアップ完了を待つ  
3. `C:\Projects` で開発  
4. `C:\Logs` の検証ログを必要時に保管  
5. Sandbox 終了（中の状態は破棄）

### 5.3 更新運用（管理者）

1. `env.lock.json` のバージョンを更新  
2. 代表端末で起動検証  
3. 問題なければ Git で配布  
4. 全員が次回起動時に同一更新を取得

---

## 6. Hyper-V との違い（実務観点で深掘り）

### 6.1 状態管理モデルの違い

- Sandbox: 毎回クリーン。状態はコードで再現する  
- Hyper-V: 状態を保持。運用ルールが弱いと個体差が蓄積する

### 6.2 容量増加の根本原因

Hyper-V が肥大化する原因は次です。

- OS + ツール導入でVHDXの初期サイズが大きい
- チェックポイント連鎖で差分ディスクが増える
- VMごとに同じツールを重複保持する

Sandbox では、環境定義と成果物のみを保持するため、同じ問題が発生しにくいです。

### 6.3 複製/共有モデルの違い

- Sandbox: `.wsb` + `scripts` + `config` を配れば即共有できる
- Hyper-V: VM複製にはエクスポート/インポートとストレージ転送が必要

---

## 7. Hyper-V バックアップ/流用を破綻させない方法

Hyper-V を完全排除しない前提で、以下の設計に固定します。

### 7.1 VM種別を固定する

- `template-base`: OSのみ、更新済み
- `template-gpu`: GPU必須ツール入り
- `work-*`: 案件用作業VM（必要時のみ作成）

テンプレート以外を増やさないことが最優先です。

### 7.2 チェックポイント運用ルール

- 作成タイミングは「大きな変更前」のみ
- 命名規則: `YYYYMMDD-purpose`
- 不要チェックポイントは定期削除
- チェックポイントを“履歴管理”用途に使わない

### 7.3 バックアップ方針（3層）

1. 成果物バックアップ（最優先）  
`C:\DevPlatform\projects` とコードリポジトリを日次バックアップ

2. 環境定義バックアップ（次点）  
`C:\DevPlatform\sandbox` と運用スクリプトをGit + 定期アーカイブ

3. Hyper-V エクスポート（例外）  
`template-base` / `template-gpu` のみ週次エクスポートし、`C:\DevPlatform\hyperv\exports` に保存

### 7.4 流用手順（Hyper-V）

1. テンプレートVMを月次更新  
2. 更新後にエクスポート  
3. 新案件はエクスポートからインポートして `work-*` を作成  
4. 案件終了で `work-*` を削除し、成果物のみ残す

この運用にすると、巨大なVMを常時バックアップし続ける必要がなくなります。

---

## 8. GPU問題の扱い

実務では「GPUはSandboxで必ず使える前提」にしないことが重要です。

- CPU中心タスク: Sandbox標準運用
- GPU必須タスク: Hyper-V `template-gpu` か物理実行
- どちらか不明なタスク: 先に小さな検証ジョブで判定してから実行環境を決める

---

## 9. チーム運用ルール（必須）

- `env.lock.json` 変更はレビュー必須
- `.wsb` と `scripts` は同一リポジトリで版管理
- ローカル独自変更は禁止（必要ならPR化）
- 障害時は `verify-*.log` を一次情報として確認
- 「起動できるが再現できない」状態を放置しない

---

## 10. 最終提案

あなたの要件では、次の運用が最適です。

- 標準開発: Windows Sandbox
- 環境保証: `env.lock.json` + `bootstrap.ps1` + `verify.ps1`
- 例外処理: Hyper-V テンプレート最小運用
- バックアップ優先順位: 成果物 > 環境定義 > テンプレートVM

この構成なら、容量コスト・配布容易性・再現性・GPU例外対応を同時に満たせます。
