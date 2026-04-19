# Test driver: accordion menu
# Dot-sources private functions directly to avoid module dependency issues.
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

. "$root/Private/AnsiPalette.ps1"
. "$root/Private/AnsiGradient.ps1"
. "$root/Private/AnsiWidth.ps1"
. "$root/Private/AnsiCapability.ps1"
. "$root/Private/RenderMenuBox.ps1"
. "$root/Private/UIHelpers.ps1"
. "$root/Private/RenderAccordionBox.ps1"
. "$root/Private/MenuArrowAccordion.ps1"

$script:HasArrowKeySupport = Test-InTUIArrowKeySupport

$sections = @(
    @{ Title = 'Endpoint Management'; Items = @('Devices', 'Apps', 'Users', 'Groups') }
    @{ Title = 'Policy & Compliance'; Items = @('Config Profiles', 'Compliance', 'Conditional Access') }
    @{ Title = 'Tools'; Items = @('Search', 'Bookmarks', 'Settings') }
    @{ Title = 'Quick Action'; Items = @(); IsDirect = $true }
)

Clear-Host
$result = Show-InTUIMenuArrowAccordion -Title 'Test Menu' -Sections $sections
if ($result) {
    Write-Host "SELECTED:$($result.ItemText)"
    Write-Host "SECTION:$($result.SectionIndex)"
    Write-Host "ITEM:$($result.ItemIndex)"
}
else {
    Write-Host 'CANCELLED'
}
