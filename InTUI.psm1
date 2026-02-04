#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication, PwshSpectreConsole

# InTUI - Intune Terminal User Interface
# A Spectre Console based TUI for Microsoft Intune management

$script:InTUIVersion = '1.0.0'
$script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'
$script:GraphBetaUrl = 'https://graph.microsoft.com/beta'
$script:PageSize = 50
$script:Connected = $false

# Import all private functions
$PrivateFunctions = Get-ChildItem -Path "$PSScriptRoot/Private/*.ps1" -ErrorAction SilentlyContinue
foreach ($Function in $PrivateFunctions) {
    try {
        . $Function.FullName
    }
    catch {
        Write-Error "Failed to import $($Function.FullName): $_"
    }
}

# Import all public functions
$PublicFunctions = Get-ChildItem -Path "$PSScriptRoot/Public/*.ps1" -ErrorAction SilentlyContinue
foreach ($Function in $PublicFunctions) {
    try {
        . $Function.FullName
    }
    catch {
        Write-Error "Failed to import $($Function.FullName): $_"
    }
}

# Import all view functions
$ViewFunctions = Get-ChildItem -Path "$PSScriptRoot/Views/*.ps1" -ErrorAction SilentlyContinue
foreach ($Function in $ViewFunctions) {
    try {
        . $Function.FullName
    }
    catch {
        Write-Error "Failed to import $($Function.FullName): $_"
    }
}

Export-ModuleMember -Function 'Start-InTUI', 'Connect-InTUI'
