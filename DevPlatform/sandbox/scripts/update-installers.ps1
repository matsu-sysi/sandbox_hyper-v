$ErrorActionPreference = 'Stop'

# 目的:
# - 最新安定版インストーラ一式をローカルキャッシュへ更新する
# - 取得結果を manifest(JSON) で証跡化する
$scriptRoot = Split-Path -Parent $PSCommandPath
$sandboxRoot = Split-Path -Parent $scriptRoot
$installersDir = Join-Path $sandboxRoot 'cache\installers'
New-Item -ItemType Directory -Path $installersDir -Force | Out-Null

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

function Save-File([string]$url, [string]$outFile) {
  # 単純なダウンロード関数（エラー時は停止）
  Invoke-WebRequest -Uri $url -OutFile $outFile -UseBasicParsing
}

$items = @()

$vscodeUrl = 'https://update.code.visualstudio.com/latest/win32-x64-user/stable'
$vscodeFile = Join-Path $installersDir 'VSCodeUserSetup-x64-latest.exe'
Save-File -url $vscodeUrl -outFile $vscodeFile
$items += [pscustomobject]@{ name='VSCode'; version='latest-stable'; file=(Split-Path -Leaf $vscodeFile); url=$vscodeUrl }

$gitApi = 'https://api.github.com/repos/git-for-windows/git/releases/latest'
$gitRel = Invoke-RestMethod -Uri $gitApi -Headers @{ 'User-Agent' = 'DevPlatformInstallerUpdater' }
$gitAsset = $gitRel.assets | Where-Object { $_.name -match '^Git-.*-64-bit\.exe$' } | Select-Object -First 1
$gitFile = Join-Path $installersDir $gitAsset.name
Save-File -url $gitAsset.browser_download_url -outFile $gitFile
$items += [pscustomobject]@{ name='Git'; version=$gitRel.tag_name; file=(Split-Path -Leaf $gitFile); url=$gitAsset.browser_download_url }

$nodeIndex = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json'
$nodeLts = $nodeIndex | Where-Object { $_.lts -and ($_.files -contains 'win-x64-msi') } | Select-Object -First 1
$nodeVersion = $nodeLts.version.TrimStart('v')
$nodeUrl = "https://nodejs.org/dist/v$nodeVersion/node-v$nodeVersion-x64.msi"
$nodeFile = Join-Path $installersDir "node-v$nodeVersion-x64.msi"
Save-File -url $nodeUrl -outFile $nodeFile
$items += [pscustomobject]@{ name='Node.js LTS'; version="v$nodeVersion"; file=(Split-Path -Leaf $nodeFile); url=$nodeUrl }

$pythonPage = Invoke-WebRequest -Uri 'https://www.python.org/downloads/windows/' -UseBasicParsing
$match = [regex]::Match($pythonPage.Content, 'https://www\.python\.org/ftp/python/(?<ver>\d+\.\d+\.\d+)/python-(?<ver2>\d+\.\d+\.\d+)-amd64\.exe')
$pyVer = $match.Groups['ver'].Value
$pyUrl = $match.Value
$pyFile = Join-Path $installersDir "python-$pyVer-amd64.exe"
Save-File -url $pyUrl -outFile $pyFile
$items += [pscustomobject]@{ name='Python'; version=$pyVer; file=(Split-Path -Leaf $pyFile); url=$pyUrl }

$manifest = [ordered]@{
  generated_at = (Get-Date).ToString('o')
  items = @()
}

foreach ($item in $items) {
  $full = Join-Path $installersDir $item.file
  $manifest.items += [ordered]@{
    name = $item.name
    version = $item.version
    file = $full
    url = $item.url
    sha256 = (Get-FileHash -Algorithm SHA256 -Path $full).Hash
    size_bytes = (Get-Item $full).Length
  }
}

$manifestPath = Join-Path $installersDir 'installers.manifest.json'
$manifest | ConvertTo-Json -Depth 6 | Set-Content -Path $manifestPath -Encoding UTF8
Write-Host "Updated installers: $installersDir" -ForegroundColor Green

