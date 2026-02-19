$ErrorActionPreference = 'Stop'

# 目的:
# - Sandbox起動直後の開発環境初期化
# - ローカルインストーラ優先で導入
# - 1起動1ログ(run-<id>.log)へ追記する

$sessionPath = 'C:\Config\session.json'
if (Test-Path $sessionPath) {
  $session = Get-Content -Raw $sessionPath | ConvertFrom-Json
  $bootstrapLog = $session.RunLogPathInSandbox
}
else {
  $timestamp = Get-Date -Format yyyyMMdd-HHmmss
  $bootstrapLog = "C:\Logs\bootstrap-$timestamp.log"
}

Start-Transcript -Path $bootstrapLog -Append -Force | Out-Null

function Test-CommandExists([string]$name) {
  return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Add-ToPathIfExists([string]$path) {
  if (Test-Path $path) {
    $env:Path = "$path;$env:Path"
    Write-Host "Added to PATH: $path" -ForegroundColor DarkCyan
  }
}

function Refresh-SessionPath {
  $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
  if ($machinePath -and $userPath) {
    $env:Path = "$machinePath;$userPath"
  }
  elseif ($machinePath) {
    $env:Path = $machinePath
  }
}

function Install-FromLocalInstaller($pkg) {
  $installerPath = Join-Path 'C:\Installers' $pkg.installerFile
  if (-not (Test-Path $installerPath)) {
    throw "Local installer not found: $installerPath"
  }

  Write-Host "Installing $($pkg.id) from local installer..." -ForegroundColor Yellow
  $timeoutSec = 600
  if ($pkg.timeoutSec) {
    $timeoutSec = [int]$pkg.timeoutSec
  }

  $proc = $null
  if ($pkg.installerType -eq 'msi') {
    $args = "/i `"$installerPath`" $($pkg.silentArgs)"
    $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $args -PassThru
  }
  else {
    $proc = Start-Process -FilePath $installerPath -ArgumentList $pkg.silentArgs -PassThru
  }

  if (-not $proc.WaitForExit($timeoutSec * 1000)) {
    try { $proc.Kill() } catch {}
    throw "Installer timed out after $timeoutSec sec: $($pkg.installerFile)"
  }

  if ($proc.ExitCode -ne 0) {
    throw "Installer exit code $($proc.ExitCode): $($pkg.installerFile)"
  }
}

function Install-FromWinget($pkg) {
  Write-Host "Fallback(winget): Installing $($pkg.id) $($pkg.version)" -ForegroundColor Yellow
  winget install --id $pkg.id --version $pkg.version -e --accept-source-agreements --accept-package-agreements --disable-interactivity
}

function Install-VSCodeExtensions([string[]]$extensionIds) {
  foreach ($ext in $extensionIds) {
    Write-Host "Installing VS Code extension: $ext" -ForegroundColor Yellow
    try {
      code --install-extension $ext --force
    }
    catch {
      Write-Warning "Failed to install VS Code extension: $ext"
    }
  }
}

try {
  Add-ToPathIfExists 'C:\HostTools\VSCodeBin'
  Add-ToPathIfExists 'C:\HostTools\GitCmd'
  Add-ToPathIfExists 'C:\HostTools\GitBin'

  $mark2Reg = 'C:\Config\mark2-bootstrap.reg'
  if (Test-Path $mark2Reg) {
    Write-Host 'Importing Mark2 HKCU bootstrap registry...' -ForegroundColor Cyan
    reg import $mark2Reg | Out-Null
  }

  $lock = Get-Content C:\Config\env.lock.json -Raw | ConvertFrom-Json
  $failedPackages = New-Object System.Collections.Generic.List[string]

  foreach ($pkg in $lock.packages) {
    if ($null -ne $pkg.autoInstall -and -not [bool]$pkg.autoInstall) {
      Write-Host "Skipping $($pkg.id): autoInstall=false." -ForegroundColor DarkYellow
      continue
    }

    if ($pkg.command -and (Test-CommandExists -name $pkg.command)) {
      Write-Host "Skipping $($pkg.id): '$($pkg.command)' already exists." -ForegroundColor DarkGreen
      continue
    }

    try {
      Install-FromLocalInstaller -pkg $pkg
    }
    catch {
      if ($lock.useWingetFallback -eq $true -and (Get-Command winget -ErrorAction SilentlyContinue)) {
        try {
          Install-FromWinget -pkg $pkg
        }
        catch {
          $failedPackages.Add("$($pkg.id): $($_.Exception.Message)") | Out-Null
        }
      }
      else {
        $failedPackages.Add("$($pkg.id): $($_.Exception.Message)") | Out-Null
      }
    }
  }

  Refresh-SessionPath
  # PATH再読込で消えるため、ホストツール参照を再追加する。
  Add-ToPathIfExists 'C:\HostTools\VSCodeBin'
  Add-ToPathIfExists 'C:\HostTools\GitCmd'
  Add-ToPathIfExists 'C:\HostTools\GitBin'

  if (Test-CommandExists -name 'code') {
    Install-VSCodeExtensions -extensionIds $lock.vscodeExtensions
  }
  else {
    Write-Warning 'VS Code command (code) is not available after setup.'
  }

  if (Test-Path 'C:\Bootstrap\verify.ps1') {
    & C:\Bootstrap\verify.ps1
  }

  if ($failedPackages.Count -gt 0) {
    Write-Warning 'Some package installs failed:'
    $failedPackages | ForEach-Object { Write-Warning $_ }
  }

  Start-Process explorer.exe C:\Projects
}
finally {
  Stop-Transcript | Out-Null
}
