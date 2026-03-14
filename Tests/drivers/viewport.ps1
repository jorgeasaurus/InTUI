# Test driver: single-select with many items to test viewport scrolling
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

. "$root/Private/AnsiPalette.ps1"
. "$root/Private/AnsiGradient.ps1"
. "$root/Private/AnsiWidth.ps1"
. "$root/Private/AnsiCapability.ps1"
. "$root/Private/RenderMenuBox.ps1"
. "$root/Private/MenuArrowSingle.ps1"

# Generate 30 items to force viewport scrolling in a 40-row terminal
$choices = 1..30 | ForEach-Object { "Item $_" }

Clear-Host
$result = Show-InTUIMenuArrowSingle -Title 'Viewport Test' -Choices $choices -IncludeBack
if ($result -eq 'Back') {
    Write-Host 'BACK'
}
elseif ($result -is [int]) {
    Write-Host "INDEX:$result"
    Write-Host "CHOICE:$($choices[$result])"
}
