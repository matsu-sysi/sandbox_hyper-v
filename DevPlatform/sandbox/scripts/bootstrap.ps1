$ErrorActionPreference = 'Stop'

$timestamp = Get-Date -Format yyyyMMdd-HHmmss
$bootstrapLog = "C:\Logs\bootstrap-$timestamp.log"
Start-Transcript -Path $bootstrapLog -Force | Out-Null

function Test-CommandExists([string]$name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Install-PackageWithFallback($pkg) {
  Write-Host "Installing $($pkg.id) $($pkg.version)" -ForegroundColor Yellow

  try {
    winget install --id $pkg.id --version $pkg.version -e --accept-source-agreements --accept-package-agreements --disable-interactivity
    return
  }
  catch {
    Write-Warning "Version-pinned install failed for $($pkg.id). Retrying without version."
  }

  winget install --id $pkg.id -e --accept-source-agreements --accept-package-agreements --disable-interactivity
}

try {
  Write-Host '== Network check ==' -ForegroundColor Cyan
  Resolve-DnsName github.com | Out-Null
  Test-NetConnection github.com -Port 443 | Out-Null
  Resolve-DnsName learn.microsoft.com | Out-Null
  Test-NetConnection learn.microsoft.com -Port 443 | Out-Null

  $mark2Reg = 'C:\Config\mark2-bootstrap.reg'
  if (Test-Path $mark2Reg) {
    Write-Host 'Importing Mark2 HKCU bootstrap registry...' -ForegroundColor Cyan
    reg import $mark2Reg | Out-Null
  }

  $lock = Get-Content C:\Config\env.lock.json -Raw | ConvertFrom-Json

  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) {
    Write-Warning 'winget is not available. Skipping package installation.'
  }
  else {
    foreach ($pkg in $lock.packages) {
      Install-PackageWithFallback -pkg $pkg
    }
  }

  if (Test-CommandExists -name 'code') {
    & C:\Bootstrap\setup-vscode.ps1 -ExtensionIds $lock.vscodeExtensions
  }
  else {
    Write-Warning 'VS Code command (code) is not available after setup.'
  }

  & C:\Bootstrap\verify.ps1
  Start-Process explorer.exe C:\Projects
}
finally {
  Stop-Transcript | Out-Null
}
