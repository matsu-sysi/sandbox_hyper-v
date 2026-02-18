param(
  [switch]$NoLaunch
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSCommandPath
$scriptsPath = Join-Path $projectRoot 'sandbox\scripts'
$configPath = Join-Path $projectRoot 'sandbox\config'
$logsPath = Join-Path $projectRoot 'sandbox\logs'
$projectsPath = Join-Path $projectRoot 'projects'

$requiredHostPaths = @($scriptsPath, $configPath, $logsPath, $projectsPath)

$missing = $requiredHostPaths | Where-Object { -not (Test-Path $_) }
if ($missing) {
  throw "Required path(s) missing:`n$($missing -join "`n")"
}

$generatedWsb = Join-Path $projectRoot 'sandbox\wsb\dev-online-16gb.generated.wsb'
$extraMappingsPath = Join-Path $configPath 'extra-mapped-folders.json'

function Escape-Xml([string]$value) {
  return [System.Security.SecurityElement]::Escape($value)
}

function New-MappedFolderXml([string]$hostFolder, [string]$sandboxFolder, [bool]$readOnly) {
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

$mappedFolderEntries = @()
$mappedFolderEntries += New-MappedFolderXml -hostFolder $scriptsPath -sandboxFolder 'C:\Bootstrap' -readOnly $true
$mappedFolderEntries += New-MappedFolderXml -hostFolder $configPath -sandboxFolder 'C:\Config' -readOnly $true
$mappedFolderEntries += New-MappedFolderXml -hostFolder $logsPath -sandboxFolder 'C:\Logs' -readOnly $false
$mappedFolderEntries += New-MappedFolderXml -hostFolder $projectsPath -sandboxFolder 'C:\Projects' -readOnly $false

if (Test-Path $extraMappingsPath) {
  $extraMappings = Get-Content -Raw $extraMappingsPath | ConvertFrom-Json
  foreach ($m in $extraMappings) {
    $mappedFolderEntries += New-MappedFolderXml `
      -hostFolder $m.HostFolder `
      -sandboxFolder $m.SandboxFolder `
      -readOnly ([bool]$m.ReadOnly)
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
