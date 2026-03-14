# Test driver: multi-select menu
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

. "$root/Private/AnsiPalette.ps1"
. "$root/Private/AnsiGradient.ps1"
. "$root/Private/AnsiWidth.ps1"
. "$root/Private/AnsiCapability.ps1"
. "$root/Private/RenderMenuBox.ps1"
. "$root/Private/MenuArrowMulti.ps1"

$choices = @('Windows', 'macOS', 'iOS', 'Android', 'Linux')

Clear-Host
$result = Show-InTUIMenuArrowMulti -Title 'Select platforms' -Choices $choices -IncludeBack
if ($result.Count -eq 0) {
    Write-Host 'NONE'
}
else {
    foreach ($idx in $result) {
        Write-Host "SELECTED:$($choices[$idx])"
    }
}
