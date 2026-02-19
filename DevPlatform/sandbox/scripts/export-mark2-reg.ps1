$ErrorActionPreference = 'Stop'

# 目的:
# - ホストの Mark2 レジストリ(HKCU)を bootstrap 用 .reg に出力する
# - 次回Sandbox起動時の初期状態として import させる
$scriptRoot = Split-Path -Parent $PSCommandPath
$configDir = Join-Path (Split-Path -Parent $scriptRoot) 'config'
$output = Join-Path $configDir 'mark2-bootstrap.reg'

if (-not (Test-Path 'HKCU:\Software\System-I\Mark2')) {
  throw 'Registry key HKCU:\Software\System-I\Mark2 was not found on host.'
}

reg export "HKCU\Software\System-I\Mark2" "$output" /y | Out-Null
Write-Host "Exported: $output" -ForegroundColor Green

