param(
  [Parameter(Mandatory = $true)]
  [string[]]$ExtensionIds
)

foreach ($ext in $ExtensionIds) {
  Write-Host "Installing VS Code extension: $ext" -ForegroundColor Yellow
  code --install-extension $ext --force
}
