$timestamp = Get-Date -Format yyyyMMdd-HHmmss
$logFile = "C:\Logs\verify-$timestamp.log"

function Get-VersionOrMissing([string]$command, [scriptblock]$versionExpr) {
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
    return "$command: MISSING"
  }
  try {
    return & $versionExpr
  }
  catch {
    return "$command: ERROR ($($_.Exception.Message))"
  }
}

$lines = @()
$lines += Get-VersionOrMissing 'git' { "git: $(git --version)" }
$lines += Get-VersionOrMissing 'code' { "code: $((code --version | Select-Object -First 1))" }
$lines += Get-VersionOrMissing 'python' { "python: $(python --version)" }
$lines += Get-VersionOrMissing 'node' { "node: $(node --version)" }
$lines += "time: $(Get-Date -Format o)"

$lines | Out-File -FilePath $logFile -Encoding utf8
Write-Host "Wrote verification log to $logFile" -ForegroundColor Green
