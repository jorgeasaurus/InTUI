# Test driver: single-select menu
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

. "$root/Private/AnsiPalette.ps1"
. "$root/Private/AnsiGradient.ps1"
. "$root/Private/AnsiWidth.ps1"
. "$root/Private/AnsiCapability.ps1"
. "$root/Private/RenderMenuBox.ps1"
. "$root/Private/MenuArrowSingle.ps1"

$choices = @('Devices', 'Apps', 'Users', 'Groups', 'Configuration Profiles',
             'Compliance Policies', 'Conditional Access', 'Reports', 'Back')

Clear-Host
$result = Show-InTUIMenuArrowSingle -Title 'Select an option' -Choices $choices -IncludeBack
if ($result -eq 'Back') {
    Write-Host 'BACK'
}
elseif ($result -is [int]) {
    Write-Host "INDEX:$result"
    Write-Host "CHOICE:$($choices[$result])"
}
