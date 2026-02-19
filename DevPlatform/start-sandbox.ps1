param(
  [switch]$NoLaunch,
  [switch]$ForceRestart,
  [string]$RunId,
  [string]$LogDate
)

# 目的:
# - 配置場所に依存しない .wsb を都度生成する
# - 起動前エラーをホスト側ログに残す
# - ログを 日付フォルダ/run-<起動ID>.log に1本化する
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSCommandPath
$logsBasePath = Join-Path $projectRoot 'sandbox\logs'
New-Item -ItemType Directory -Path $logsBasePath -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = Get-Date -Format yyyyMMdd-HHmmss }
if ([string]::IsNullOrWhiteSpace($LogDate)) { $LogDate = Get-Date -Format yyyy-MM-dd }

$logsPath = Join-Path $logsBasePath $LogDate
New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
$launcherLog = Join-Path $logsPath "run-$RunId.log"
Start-Transcript -Path $launcherLog -Append -Force | Out-Null

function Get-RunningSandboxProcesses {
  # Sandboxが稼働中かどうかを判定する最小プロセスのみ対象にする。
  return Get-Process -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessName -in @('WindowsSandboxRemoteSession', 'WindowsSandboxServer')
  }
}

function Stop-RunningSandboxProcesses {
  # -ForceRestart 指定時のみ、残留プロセスを停止して再起動可能にする。
  $procs = Get-RunningSandboxProcesses
  if (-not $procs) { return }

  foreach ($p in $procs) {
    try {
      Stop-Process -Id $p.Id -Force -ErrorAction Stop
    }
    catch {
      Write-Warning "Failed to stop process $($p.ProcessName)($($p.Id)): $($_.Exception.Message)"
    }
  }

  Start-Sleep -Seconds 2
}

function Escape-Xml([string]$value) {
  # XMLに埋め込むパス文字列をエスケープする。
  return [System.Security.SecurityElement]::Escape($value)
}

function New-MappedFolderXml([string]$hostFolder, [string]$sandboxFolder, [bool]$readOnly) {
  # 1マウント分のXMLを生成する。存在しないホストパスはエラーにする。
  if (-not (Test-Path $hostFolder)) {
    throw "Mapped host folder does not exist: $hostFolder"
  }

  $hostFolderEscaped = Escape-Xml $hostFolder
  $sandboxFolderEscaped = Escape-Xml $sandboxFolder
  $readOnlyText = if ($readOnly) { 'true' } else { 'false' }

  return @"
    <MappedFolder>
      <HostFolder>$hostFolderEscaped</HostFolder>
      <SandboxFolder>$sandboxFolderEscaped</SandboxFolder>
      <ReadOnly>$readOnlyText</ReadOnly>
    </MappedFolder>
"@
}

$scriptsPath = Join-Path $projectRoot 'sandbox\scripts'
$configPath = Join-Path $projectRoot 'sandbox\config'
$installersPath = Join-Path $projectRoot 'sandbox\cache\installers'
$projectsPath = Join-Path $projectRoot 'projects'
$requiredHostPaths = @($scriptsPath, $configPath, $logsPath, $projectsPath, $installersPath)

try {
  Write-Host "Launcher log: $launcherLog" -ForegroundColor Cyan

  $missing = $requiredHostPaths | Where-Object { -not (Test-Path $_) }
  if ($missing) {
    throw "Required path(s) missing:`n$($missing -join "`n")"
  }

  $runningSandbox = Get-RunningSandboxProcesses
  if ($runningSandbox) {
    if ($ForceRestart) {
      Write-Warning 'Existing Windows Sandbox processes detected. Forcing cleanup...'
      Stop-RunningSandboxProcesses
      $runningSandbox = Get-RunningSandboxProcesses
      if ($runningSandbox) {
        $left = $runningSandbox | ForEach-Object { "$($_.ProcessName)($($_.Id))" }
        throw "Failed to clean up running sandbox processes:`n$($left -join "`n")"
      }
    }
    else {
      $list = $runningSandbox | ForEach-Object { "$($_.ProcessName)($($_.Id))" }
      throw "Windows Sandbox is still running:`n$($list -join "`n")`nClose it or run: .\start-sandbox.ps1 -ForceRestart"
    }
  }

  $generatedWsb = Join-Path $projectRoot 'sandbox\wsb\dev-online-16gb.generated.wsb'
  $extraMappingsPath = Join-Path $configPath 'extra-mapped-folders.json'
  $hostToolsPath = Join-Path $configPath 'host-tools.json'
  $sessionPath = Join-Path $configPath 'session.json'

  # Sandbox側スクリプトが同じログファイルへ追記できるようセッション情報を共有する。
  $session = [ordered]@{
    RunId = $RunId
    LogDate = $LogDate
    RunLogPathInSandbox = "C:\Logs\run-$RunId.log"
  }
  $session | ConvertTo-Json -Depth 4 | Set-Content -Path $sessionPath -Encoding UTF8

  $mappedFolderEntries = @()
  $mappedFolderEntries += New-MappedFolderXml -hostFolder $scriptsPath -sandboxFolder 'C:\Bootstrap' -readOnly $true
  $mappedFolderEntries += New-MappedFolderXml -hostFolder $configPath -sandboxFolder 'C:\Config' -readOnly $true
  $mappedFolderEntries += New-MappedFolderXml -hostFolder $logsPath -sandboxFolder 'C:\Logs' -readOnly $false
  $mappedFolderEntries += New-MappedFolderXml -hostFolder $installersPath -sandboxFolder 'C:\Installers' -readOnly $true
  $mappedFolderEntries += New-MappedFolderXml -hostFolder $projectsPath -sandboxFolder 'C:\Projects' -readOnly $false

  if (Test-Path $extraMappingsPath) {
    $extraMappings = Get-Content -Raw $extraMappingsPath | ConvertFrom-Json
    foreach ($m in $extraMappings) {
      $mappedFolderEntries += New-MappedFolderXml -hostFolder $m.HostFolder -sandboxFolder $m.SandboxFolder -readOnly ([bool]$m.ReadOnly)
    }
  }

  if (Test-Path $hostToolsPath) {
    $hostTools = Get-Content -Raw $hostToolsPath | ConvertFrom-Json
    foreach ($t in $hostTools) {
      if ($t.Enabled -eq $false) { continue }
      if (-not (Test-Path $t.HostFolder)) {
        Write-Warning "Host tool path not found. Skipped: $($t.HostFolder)"
        continue
      }
      $mappedFolderEntries += New-MappedFolderXml -hostFolder $t.HostFolder -sandboxFolder $t.SandboxFolder -readOnly $true
    }
  }

  $mappedFoldersXml = ($mappedFolderEntries -join "`r`n")

  $xml = @"
<Configuration>
  <vGPU>Enable</vGPU>
  <Networking>Enable</Networking>
  <ClipboardRedirection>Enable</ClipboardRedirection>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <PrinterRedirection>Disable</PrinterRedirection>
  <MappedFolders>
$mappedFoldersXml
  </MappedFolders>
  <MemoryInMB>16384</MemoryInMB>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -File C:\Bootstrap\bootstrap.ps1</Command>
  </LogonCommand>
</Configuration>
"@

  $xml | Set-Content -Path $generatedWsb -Encoding UTF8
  if (-not $NoLaunch) {
    Start-Process -FilePath $generatedWsb
  }
}
catch {
  Write-Error $_
  throw
}
finally {
  Stop-Transcript | Out-Null
}
