#Requires -Version 7.2
#Requires -Modules Microsoft.Graph.Authentication, PwshSpectreConsole

# InTUI - Intune Terminal User Interface
# A Spectre Console based TUI for Microsoft Intune management

$script:InTUIVersion = '1.0.0'
$script:PageSize = 50
$script:Connected = $false
$script:CloudEnvironment = 'Global'

# Cache settings
$script:CachePath = Join-Path $HOME '.intui_cache'
$script:CacheEnabled = $true
$script:CacheTTL = 300  # 5 minutes default

# Recording settings
$script:RecordingEnabled = $false
$script:RecordedActions = $null
$script:RecordingStartTime = $null
$script:RecordingEndTime = $null

# Bookmarks
$script:BookmarksPath = Join-Path $HOME '.intui_bookmarks.json'

# Cloud environment definitions
# GCC uses worldwide endpoints; GCC High uses graph.microsoft.us
# See: https://learn.microsoft.com/en-us/graph/deployments
$script:CloudEnvironments = @{
    'Global' = @{
        GraphBaseUrl = 'https://graph.microsoft.com/v1.0'
        GraphBetaUrl = 'https://graph.microsoft.com/beta'
        MgEnvironment = 'Global'
        Label = 'Commercial / GCC (Global)'
    }
    'USGov' = @{
        GraphBaseUrl = 'https://graph.microsoft.us/v1.0'
        GraphBetaUrl = 'https://graph.microsoft.us/beta'
        MgEnvironment = 'USGov'
        Label = 'US Government (GCC High)'
    }
    'USGovDoD' = @{
        GraphBaseUrl = 'https://dod-graph.microsoft.us/v1.0'
        GraphBetaUrl = 'https://dod-graph.microsoft.us/beta'
        MgEnvironment = 'USGovDoD'
        Label = 'US Government (DoD)'
    }
    'China' = @{
        GraphBaseUrl = 'https://microsoftgraph.chinacloudapi.cn/v1.0'
        GraphBetaUrl = 'https://microsoftgraph.chinacloudapi.cn/beta'
        MgEnvironment = 'China'
        Label = 'China (21Vianet)'
    }
}

$script:GraphBaseUrl = $script:CloudEnvironments['Global'].GraphBaseUrl
$script:GraphBetaUrl = $script:CloudEnvironments['Global'].GraphBetaUrl

foreach ($folder in 'Private', 'Public', 'Views') {
    foreach ($file in Get-ChildItem -Path "$PSScriptRoot/$folder/*.ps1" -ErrorAction SilentlyContinue) {
        try {
            . $file.FullName
        }
        catch {
            Write-Error "Failed to import $($file.FullName): $_"
        }
    }
}

Export-ModuleMember -Function 'Start-InTUI', 'Connect-InTUI', 'Export-InTUIData'
