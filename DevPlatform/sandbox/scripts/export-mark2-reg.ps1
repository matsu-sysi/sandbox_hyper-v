$ErrorActionPreference = 'Stop'

$scriptRoot = Split-Path -Parent $PSCommandPath
$configDir = Join-Path (Split-Path -Parent $scriptRoot) 'config'
$output = Join-Path $configDir 'mark2-bootstrap.reg'

if (-not (Test-Path 'HKCU:\Software\System-I\Mark2')) {
  throw 'Registry key HKCU:\Software\System-I\Mark2 was not found on host.'
}

reg export "HKCU\Software\System-I\Mark2" "$output" /y | Out-Null
Write-Host "Exported: $output" -ForegroundColor Green
