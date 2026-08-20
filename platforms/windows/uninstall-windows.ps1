param(
  [string]$RefreshVersion
)

$ErrorActionPreference = "Stop"
$stateRoot = Join-Path $env:APPDATA "NiuLaiMarketPets"
$rollbackRoot = Join-Path $stateRoot "rollback"
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{D3D1D617-0F28-4B05-A24D-5F6F9FD6CB72}_is1"

if ($RefreshVersion) {
  if (-not (Test-Path -LiteralPath $uninstallKey)) {
    New-Item -ItemType Directory -Path $uninstallKey -Force | Out-Null
  }
  New-ItemProperty -LiteralPath $uninstallKey -Name "DisplayVersion" -Value $RefreshVersion -PropertyType String -Force | Out-Null
  exit 0
}

if (Test-Path $runKey) {
  Remove-ItemProperty -Path $runKey -Name "NiuLaiMarketPets" -ErrorAction SilentlyContinue
}

if (Test-Path -LiteralPath $uninstallKey) {
  Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path $stateRoot) {
  $backup = Join-Path $rollbackRoot $stamp
  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  $config = Join-Path $stateRoot "config.json"
  if (Test-Path $config) { Move-Item $config (Join-Path $backup "config.json") -Force }
}

Write-Output "Windows startup removed. Config rollback retained under $rollbackRoot."
