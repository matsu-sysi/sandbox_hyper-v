# 目的:
# - 起動後に主要CLIの存在/バージョンを標準出力へ出す
# - 出力は bootstrap.ps1 の Transcript が run-<id>.log へ記録する

function Get-VersionOrMissing([string]$command, [scriptblock]$versionExpr) {
  if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
    return "${command}: MISSING"
  }
  try {
    return & $versionExpr
  }
  catch {
    return "${command}: ERROR ($($_.Exception.Message))"
  }
}

$lines = @()
$lines += ''
$lines += '----- VERIFY -----'
$lines += Get-VersionOrMissing 'git' { "git: $(git --version)" }
$lines += Get-VersionOrMissing 'code' { "code: $((code --version | Select-Object -First 1))" }
$lines += Get-VersionOrMissing 'python' { "python: $(python --version)" }
$lines += Get-VersionOrMissing 'node' { "node: $(node --version)" }
$lines += "time: $(Get-Date -Format o)"

$lines | ForEach-Object { Write-Output $_ }
