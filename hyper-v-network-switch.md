# Hyper-V ネットワーク・VM 管理ガイド

最終更新: 2026-02-19
対象: Windows 11/10 Pro・Enterprise（Hyper-V 有効化済み）

---

## 目次

1. [ネットワークスイッチの設定（内部スイッチ + ICS）](#1-ネットワークスイッチの設定内部スイッチ--ics)
2. [VM への接続方法](#2-vm-への接続方法)
3. [VM の移行・配布手順](#3-vm-の移行配布手順)
4. [vTPM トラブル：別 PC に移行後に起動できない場合](#4-vtpm-トラブル別-pc-に移行後に起動できない場合)

---

## 1. ネットワークスイッチの設定（内部スイッチ + ICS）

VM 側は**内部スイッチ**に接続し、ホスト側の**ICS（インターネット接続共有）**を経由して外部ネットに到達させる構成です。

```text
[外部ネット]
     |
[ホスト物理 NIC]  ← ICS の「共有元」
     |
[ホスト仮想 NIC（内部スイッチ側）]  ← ICS の「共有先」/ DHCP/NAT サーバーになる
     |
[内部スイッチ: dev-internal]
     |
[VM]  ← 自動で 192.168.137.x を取得、外部ネット到達可
```

### Step 1: 内部スイッチを作成する

```powershell
New-VMSwitch -Name 'dev-internal' -SwitchType Internal
```

作成すると、ホスト上に `vEthernet (dev-internal)` という仮想 NIC が自動生成されます。

### Step 2: ホスト側で ICS を有効にする

1. `Win + R` → `ncpa.cpl` を開く
2. **物理 NIC**（インターネット側）を右クリック → 「プロパティ」
3. 「共有」タブ → 「インターネット接続の共有」を有効化
4. 「ホームネットワーク接続」で **`vEthernet (dev-internal)`** を選択 → OK

`vEthernet (dev-internal)` に固定 IP `192.168.137.1` が自動設定されます。

### Step 3: VM にスイッチを割り当てる

```powershell
Connect-VMNetworkAdapter -VMName 'work-myproject' -SwitchName 'dev-internal'
```

### Step 4: VM 内で確認

```powershell
# IP が 192.168.137.x になっていること
ipconfig

# 外部疎通確認
Test-NetConnection github.com -Port 443
```

### 設定確認コマンド

```powershell
# スイッチ一覧
Get-VMSwitch

# 仮想 NIC の IP（192.168.137.1 になっていること）
Get-NetIPAddress -InterfaceAlias 'vEthernet (dev-internal)'

# ICS サービスが Running であること
Get-Service SharedAccess | Select-Object Name, Status
```

### 注意事項

- ICS 有効化時、`vEthernet (dev-internal)` の IP が **`192.168.137.1` に強制変更**されます
- 物理 NIC を切り替えた場合（Wi-Fi ↔ 有線など）、ICS の共有元を再設定する必要があります
- Windows Sandbox のネットワークは `.wsb` の `<Networking>Enable</Networking>` で独立管理されるため本手順の対象外です

---

## 2. VM への接続方法

### 方法 A: Hyper-V マネージャーから接続（VMConnect）

最もシンプルな方法。ホストに物理アクセスできる場合に使う。

```powershell
# コマンドから起動する場合
vmconnect.exe localhost 'Windows11 24H2'
```

または Hyper-V マネージャーで VM をダブルクリック。

### 方法 B: RDP（リモートデスクトップ）

ネットワーク経由で接続します。マルチモニター・クリップボード共有・ドライブリダイレクトが使えるため、実用上はこちらが快適です。

#### 前提

- VM が `dev-internal` スイッチに接続済みで `192.168.137.x` の IP を持っていること
- VM 内のアカウントにパスワードが設定されていること（パスワードなしアカウントは RDP 不可）

#### VM 内で RDP を有効化する（初回のみ）

VMConnect または PowerShell Direct で VM に入り、以下を実行します：

```powershell
# RDP を有効化
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server' `
                 -Name 'fDenyTSConnections' -Value 0

# ファイアウォールで RDP を許可
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'

# NLA（ネットワークレベル認証）を無効化（ドメイン未参加の場合に接続しやすくなる）
Set-ItemProperty -Path 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' `
                 -Name 'UserAuthentication' -Value 0
```

設定が反映されているか確認：

```powershell
# RDP が有効（0 = 有効）
Get-ItemPropertyValue 'HKLM:\System\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections'

# RDP ポート（デフォルト 3389）
Get-ItemPropertyValue 'HKLM:\System\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' 'PortNumber'
```

#### ホストから接続する

```powershell
# VM の IP を確認（192.168.137.x が表示されること）
Get-VMNetworkAdapter -VMName 'Windows11 24H2' | Select-Object -ExpandProperty IPAddresses

# RDP 接続
mstsc /v:192.168.137.x
```

オプション付きで起動する場合：

```powershell
# フルスクリーンで接続
mstsc /v:192.168.137.x /f

# 幅x高さを指定
mstsc /v:192.168.137.x /w:1920 /h:1080

# マルチモニター
mstsc /v:192.168.137.x /multimon
```

#### GUI で接続・設定を保存する

`Win + R` → `mstsc` で「リモートデスクトップ接続」を起動します。

##### 全般タブ

| 項目 | 設定値 |
| ---- | ------ |
| コンピューター(C) | `192.168.137.x`（VM の IP） |
| ユーザー名 | VM 内のアカウント名 |

入力後、「名前を付けて保存」ボタンで `.rdp` ファイルに保存しておくと次回からダブルクリックで接続できます。

##### 画面タブ

| 項目 | 推奨設定 |
| ---- | -------- |
| リモートデスクトップのサイズ | 好みの解像度、またはフルスクリーン |
| 全画面表示でマルチモニターを使用 | 複数モニター利用時はチェック |
| 色の深度 | 最高品質（32 ビット） |

##### ローカルリソースタブ

| 項目 | 推奨設定 |
| ---- | -------- |
| クリップボード | チェックあり（ホスト ↔ VM 間でコピペ可能） |
| ドライブ | 必要に応じてチェック（ホストのドライブを VM からマウント） |
| プリンター | 不要なら外す |

##### エクスペリエンスタブ

| 項目 | 推奨設定 |
| ---- | -------- |
| 接続速度 | LAN（10 Mbps 以上）← ローカル VM なのでこれを選ぶ |
| デスクトップの背景 | チェックあり |
| フォントスムージング | チェックあり |

#### .rdp ファイルに保存して使い回す（PowerShell）

GUI の「名前を付けて保存」の代わりに PowerShell で直接生成することもできます：

```powershell
$rdp = @"
full address:s:192.168.137.x
username:s:ユーザー名
screen mode id:i:2
desktopwidth:i:1920
desktopheight:i:1080
audiomode:i:0
redirectclipboard:i:1
"@
$rdp | Out-File -FilePath "V:\Windows11-24H2.rdp" -Encoding ascii
```

保存後は `Windows11-24H2.rdp` をダブルクリックするだけで接続できます。

### 方法 C: PowerShell Direct（ホスト上の VM のみ）

ネットワーク設定不要でホスト → VM に直接 PowerShell セッションを張れます。

```powershell
# 対話セッション
Enter-PSSession -VMName 'Windows11 24H2' -Credential (Get-Credential)

# 単発コマンド実行
Invoke-Command -VMName 'Windows11 24H2' -Credential (Get-Credential) -ScriptBlock {
    ipconfig
}
```

---

## 3. VM の移行・配布手順

### エクスポート前の準備（重要）

Windows 11 VM は vTPM が有効になっている場合があります。**エクスポート前に必ず無効化**してください。無効化しないと移行先 PC で起動できません（→ [セクション 4](#4-vtpm-トラブル別-pc-に移行後に起動できない場合) 参照）。

```powershell
# vTPM の状態を確認
Get-VMSecurity -VMName 'Windows11 24H2'

# vTPM が有効なら無効化してからエクスポート
Disable-VMTPM -VMName 'Windows11 24H2'
```

### エクスポート

```powershell
# VM を停止してからエクスポート
Stop-VM -VMName 'Windows11 24H2'

Export-VM -Name 'Windows11 24H2' -Path 'V:\hyperv\exports\'
```

エクスポート先に `Windows11 24H2\` フォルダが作られ、`.vmcx`・`.vhdx`・スナップショットがまとめて入ります。

### 移行先 PC でインポート

```powershell
# 1. エクスポートフォルダ内の .vmcx を確認
Get-ChildItem "V:\hyperv\exports\Windows11 24H2\" -Recurse -Filter "*.vmcx"

# 2. インポート（コピーとして登録、新しい ID を発行）
Import-VM -Path "V:\hyperv\exports\Windows11 24H2\Virtual Machines\<GUID>.vmcx" `
          -Copy -GenerateNewId `
          -VirtualMachinePath "V:\Windows11 24H2_new" `
          -VhdDestinationPath "V:\Windows11 24H2_new"

# 3. ネットワークスイッチを再割り当て（移行先でスイッチ名が異なる場合）
Connect-VMNetworkAdapter -VMName 'Windows11 24H2' -SwitchName 'dev-internal'
```

### インポートの種類

| オプション | 説明 | 用途 |
| ---------- | ---- | ---- |
| `-Copy -GenerateNewId` | ファイルをコピーして新 ID で登録 | 配布・複製 |
| `-Copy` | ファイルをコピー、元 ID を維持 | バックアップからの復元 |
| オプションなし | 既存ファイルをそのまま登録 | 別ドライブへの移動 |

### VHDX だけ渡す場合（軽量配布）

OS セットアップ済みの VHDX を渡して受け取り側が VM を新規作成する方法です。

```powershell
# 受け取り側で新規 VM を作成して既存 VHDX をアタッチ
New-VM -Name 'Windows11 24H2' `
       -Generation 2 `
       -MemoryStartupBytes 4GB `
       -VHDPath "V:\Windows11 24H2_02\Windows11 24H2.vhdx" `
       -SwitchName 'dev-internal'

# セキュアブートのテンプレートを Windows に設定
Set-VMFirmware -VMName 'Windows11 24H2' -SecureBootTemplate 'MicrosoftWindows'
```

---

## 4. vTPM トラブル：別 PC に移行後に起動できない場合

### 症状

```text
計算された認証タグが入力認証タグと一致しませんでした。(0xC000A002)
キーの保護機能をラップ解除できませんでした。(0x80070057)
```

### 原因

Windows 11 VM の vTPM 鍵は**作成元 PC の TPM に紐付いて暗号化**されています。
別 PC に持ってくると、その PC の TPM では復号できないため起動が失敗します。

```text
元の PC の TPM → vTPM 鍵を暗号化 → .vmgs / .vmcx に保存
↓ 別 PC に移行
この PC の TPM では復号できない → 0xC000A002
```

### 復旧手順

```powershell
# 1. vTPM を無効化
Disable-VMTPM -VMName 'Windows11 24H2'

# 2. vTPM が無効になったか確認（TpmEnabled: False であること）
Get-VMSecurity -VMName 'Windows11 24H2'

# 3. .vmgs ファイルの存在確認
Test-Path "V:\Windows11 24H2_02\Virtual Machines\<VM-ID>.vmgs"

# 4. VM 起動
Start-VM -VMName 'Windows11 24H2'
```

`.vmgs` が見つからない場合（リネーム済みなど）：

```powershell
Rename-Item "V:\...\<VM-ID>.vmgs.bak" "<VM-ID>.vmgs"
Start-VM -VMName 'Windows11 24H2'
```

### 予防策

**移行・エクスポート前に必ず `Disable-VMTPM` を実行する。**

```powershell
Disable-VMTPM -VMName 'Windows11 24H2'
Stop-VM -VMName 'Windows11 24H2'
Export-VM -Name 'Windows11 24H2' -Path 'V:\hyperv\exports\'
```
