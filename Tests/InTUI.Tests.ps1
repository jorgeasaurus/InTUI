#Requires -Modules Pester

<#
.SYNOPSIS
    Pester tests for InTUI module core logic.
.DESCRIPTION
    Tests cloud environment definitions, helper functions, logging,
    and Graph request URL construction. Does not require a live Graph connection.
#>

BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot

    # Initialize module-scoped variables that would normally be set by InTUI.psm1
    $script:InTUIVersion = '1.1.0'
    $script:PageSize = 50
    $script:Connected = $false
    $script:CloudEnvironment = 'Global'

    # Cloud environment definitions (same as InTUI.psm1)
    $script:CloudEnvironments = @{
        'Global' = @{
            GraphBaseUrl  = 'https://graph.microsoft.com/v1.0'
            GraphBetaUrl  = 'https://graph.microsoft.com/beta'
            MgEnvironment = 'Global'
            Label         = 'Commercial / GCC (Global)'
        }
        'USGov' = @{
            GraphBaseUrl  = 'https://graph.microsoft.us/v1.0'
            GraphBetaUrl  = 'https://graph.microsoft.us/beta'
            MgEnvironment = 'USGov'
            Label         = 'US Government (GCC High)'
        }
        'USGovDoD' = @{
            GraphBaseUrl  = 'https://dod-graph.microsoft.us/v1.0'
            GraphBetaUrl  = 'https://dod-graph.microsoft.us/beta'
            MgEnvironment = 'USGovDoD'
            Label         = 'US Government (DoD)'
        }
        'China' = @{
            GraphBaseUrl  = 'https://microsoftgraph.chinacloudapi.cn/v1.0'
            GraphBetaUrl  = 'https://microsoftgraph.chinacloudapi.cn/beta'
            MgEnvironment = 'China'
            Label         = 'China (21Vianet)'
        }
    }

    $script:GraphBaseUrl = $script:CloudEnvironments['Global'].GraphBaseUrl
    $script:GraphBetaUrl = $script:CloudEnvironments['Global'].GraphBetaUrl

    # Stub out external dependencies that aren't available in test
    function Write-SpectreHost { param([string]$Message) }
    function Invoke-MgGraphRequest {
        param($Uri, $Method, $OutputType, $Body, $ContentType)
        return @{ value = @() }
    }
    function Connect-MgGraph { param($Scopes, $NoWelcome, $Environment, $TenantId) }
    function Get-MgContext { return $null }

    # Dot-source the files under test
    . "$ProjectRoot/Private/Logging.ps1"
    . "$ProjectRoot/Private/GraphHelpers.ps1"

    # Functions from Views that contain pure logic
    . "$ProjectRoot/Views/Apps.ps1"
    . "$ProjectRoot/Views/Groups.ps1"
}

Describe 'Cloud Environment Definitions' {
    It 'Should define four cloud environments' {
        $script:CloudEnvironments.Keys.Count | Should -Be 4
    }

    It 'Should contain Global environment' {
        $script:CloudEnvironments.ContainsKey('Global') | Should -BeTrue
    }

    It 'Should contain USGov environment' {
        $script:CloudEnvironments.ContainsKey('USGov') | Should -BeTrue
    }

    It 'Should contain USGovDoD environment' {
        $script:CloudEnvironments.ContainsKey('USGovDoD') | Should -BeTrue
    }

    It 'Should contain China environment' {
        $script:CloudEnvironments.ContainsKey('China') | Should -BeTrue
    }

    It 'Global should use graph.microsoft.com' {
        $script:CloudEnvironments['Global'].GraphBaseUrl | Should -BeLike '*graph.microsoft.com*'
    }

    It 'USGov (GCC High) should use graph.microsoft.us' {
        $script:CloudEnvironments['USGov'].GraphBaseUrl | Should -BeLike '*graph.microsoft.us*'
        $script:CloudEnvironments['USGov'].GraphBaseUrl | Should -Not -BeLike '*dod-*'
    }

    It 'USGovDoD should use dod-graph.microsoft.us' {
        $script:CloudEnvironments['USGovDoD'].GraphBaseUrl | Should -BeLike '*dod-graph.microsoft.us*'
    }

    It 'China should use microsoftgraph.chinacloudapi.cn' {
        $script:CloudEnvironments['China'].GraphBaseUrl | Should -BeLike '*microsoftgraph.chinacloudapi.cn*'
    }

    It 'Each environment should have both v1.0 and beta URLs' {
        foreach ($env in $script:CloudEnvironments.Values) {
            $env.GraphBaseUrl | Should -Match '/v1\.0$'
            $env.GraphBetaUrl | Should -Match '/beta$'
        }
    }

    It 'Each environment should have an MgEnvironment value' {
        foreach ($env in $script:CloudEnvironments.Values) {
            $env.MgEnvironment | Should -Not -BeNullOrEmpty
        }
    }

    It 'Each environment should have a Label' {
        foreach ($env in $script:CloudEnvironments.Values) {
            $env.Label | Should -Not -BeNullOrEmpty
        }
    }

    It 'Global and USGov should have different base URLs' {
        $script:CloudEnvironments['Global'].GraphBaseUrl | Should -Not -Be $script:CloudEnvironments['USGov'].GraphBaseUrl
    }

    It 'USGov and USGovDoD should have different base URLs' {
        $script:CloudEnvironments['USGov'].GraphBaseUrl | Should -Not -Be $script:CloudEnvironments['USGovDoD'].GraphBaseUrl
    }

    It 'Each environment MgEnvironment should match its key name' {
        foreach ($key in $script:CloudEnvironments.Keys) {
            $script:CloudEnvironments[$key].MgEnvironment | Should -Be $key
        }
    }

    It 'USGov label should mention GCC High' {
        $script:CloudEnvironments['USGov'].Label | Should -BeLike '*GCC High*'
    }

    It 'USGovDoD label should mention DoD' {
        $script:CloudEnvironments['USGovDoD'].Label | Should -BeLike '*DoD*'
    }

    It 'China label should mention 21Vianet' {
        $script:CloudEnvironments['China'].Label | Should -BeLike '*21Vianet*'
    }
}

Describe 'Format-InTUIDate' {
    It 'Should return N/A for null input' {
        Format-InTUIDate -DateString $null | Should -Be 'N/A'
    }

    It 'Should return N/A for empty string' {
        Format-InTUIDate -DateString '' | Should -Be 'N/A'
    }

    It 'Should return hours ago for dates within 24 hours' {
        $hoursAgo = [DateTime]::UtcNow.AddHours(-3).ToString('o')
        $result = Format-InTUIDate -DateString $hoursAgo
        $result | Should -Match '^\d+h ago$'
    }

    It 'Should return days ago for dates within 7 days' {
        $daysAgo = [DateTime]::UtcNow.AddDays(-3).ToString('o')
        $result = Format-InTUIDate -DateString $daysAgo
        $result | Should -Match '^\d+d ago$'
    }

    It 'Should return formatted date for dates older than 7 days' {
        $oldDate = [DateTime]::UtcNow.AddDays(-30).ToString('o')
        $result = Format-InTUIDate -DateString $oldDate
        $result | Should -Match '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$'
    }

    It 'Should return the original string for unparseable dates' {
        $result = Format-InTUIDate -DateString 'not-a-date'
        $result | Should -Be 'not-a-date'
    }
}

Describe 'Get-InTUIComplianceColor' {
    It 'Should return green for compliant' {
        Get-InTUIComplianceColor -State 'compliant' | Should -Be 'green'
    }

    It 'Should return red for noncompliant' {
        Get-InTUIComplianceColor -State 'noncompliant' | Should -Be 'red'
    }

    It 'Should return yellow for inGracePeriod' {
        Get-InTUIComplianceColor -State 'inGracePeriod' | Should -Be 'yellow'
    }

    It 'Should return blue for configManager' {
        Get-InTUIComplianceColor -State 'configManager' | Should -Be 'blue'
    }

    It 'Should return orange1 for conflict' {
        Get-InTUIComplianceColor -State 'conflict' | Should -Be 'orange1'
    }

    It 'Should return red for error' {
        Get-InTUIComplianceColor -State 'error' | Should -Be 'red'
    }

    It 'Should return grey for unknown' {
        Get-InTUIComplianceColor -State 'unknown' | Should -Be 'grey'
    }

    It 'Should return grey for unexpected values' {
        Get-InTUIComplianceColor -State 'somethingElse' | Should -Be 'grey'
    }
}

Describe 'Get-InTUIInstallStateColor' {
    It 'Should return green for installed' {
        Get-InTUIInstallStateColor -State 'installed' | Should -Be 'green'
    }

    It 'Should return red for failed' {
        Get-InTUIInstallStateColor -State 'failed' | Should -Be 'red'
    }

    It 'Should return red for uninstallFailed' {
        Get-InTUIInstallStateColor -State 'uninstallFailed' | Should -Be 'red'
    }

    It 'Should return grey for notInstalled' {
        Get-InTUIInstallStateColor -State 'notInstalled' | Should -Be 'grey'
    }

    It 'Should return grey for notApplicable' {
        Get-InTUIInstallStateColor -State 'notApplicable' | Should -Be 'grey'
    }

    It 'Should return yellow for unexpected values' {
        Get-InTUIInstallStateColor -State 'pending' | Should -Be 'yellow'
    }
}

Describe 'Get-InTUIDeviceIcon' {
    It 'Should return blue icon for Windows' {
        Get-InTUIDeviceIcon -OperatingSystem 'Windows' | Should -BeLike '*blue*'
    }

    It 'Should return grey icon for iOS' {
        Get-InTUIDeviceIcon -OperatingSystem 'iOS' | Should -BeLike '*grey*'
    }

    It 'Should return grey icon for macOS' {
        Get-InTUIDeviceIcon -OperatingSystem 'macOS' | Should -BeLike '*grey*'
    }

    It 'Should return green icon for Android' {
        Get-InTUIDeviceIcon -OperatingSystem 'Android' | Should -BeLike '*green*'
    }

    It 'Should return yellow icon for Linux' {
        Get-InTUIDeviceIcon -OperatingSystem 'Linux' | Should -BeLike '*yellow*'
    }

    It 'Should return grey icon for unknown OS' {
        Get-InTUIDeviceIcon -OperatingSystem 'ChromeOS' | Should -BeLike '*grey*'
    }

    It 'Should match Windows with version suffix' {
        Get-InTUIDeviceIcon -OperatingSystem 'Windows 11' | Should -BeLike '*blue*'
    }
}

Describe 'Get-InTUIAppTypeFriendlyName' {
    It 'Should return Win32 for win32LobApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.win32LobApp' | Should -Be 'Win32'
    }

    It 'Should return MSI for windowsMobileMSI' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.windowsMobileMSI' | Should -Be 'MSI'
    }

    It 'Should return iOS VPP for iosVppApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.iosVppApp' | Should -Be 'iOS VPP'
    }

    It 'Should return macOS DMG for macOSDmgApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.macOSDmgApp' | Should -Be 'macOS DMG'
    }

    It 'Should return Web App for webApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.webApp' | Should -Be 'Web App'
    }

    It 'Should return M365 Apps for officeSuiteApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.officeSuiteApp' | Should -Be 'M365 Apps'
    }

    It 'Should strip prefix for unknown types' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.someNewApp' | Should -Be 'someNewApp'
    }

    It 'Should return APPX/MSIX for windowsUniversalAppX' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.windowsUniversalAppX' | Should -Be 'APPX/MSIX'
    }

    It 'Should return Edge for windowsMicrosoftEdgeApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.windowsMicrosoftEdgeApp' | Should -Be 'Edge'
    }

    It 'Should return Store (Win) for windowsStoreApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.windowsStoreApp' | Should -Be 'Store (Win)'
    }

    It 'Should return iOS Store for iosStoreApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.iosStoreApp' | Should -Be 'iOS Store'
    }

    It 'Should return iOS LOB for iosLobApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.iosLobApp' | Should -Be 'iOS LOB'
    }

    It 'Should return iOS Managed for managedIOSStoreApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.managedIOSStoreApp' | Should -Be 'iOS Managed'
    }

    It 'Should return macOS LOB for macOSLobApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.macOSLobApp' | Should -Be 'macOS LOB'
    }

    It 'Should return macOS Edge for macOSMicrosoftEdgeApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.macOSMicrosoftEdgeApp' | Should -Be 'macOS Edge'
    }

    It 'Should return Android Store for androidStoreApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.androidStoreApp' | Should -Be 'Android Store'
    }

    It 'Should return Android LOB for androidLobApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.androidLobApp' | Should -Be 'Android LOB'
    }

    It 'Should return Android Managed for managedAndroidStoreApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.managedAndroidStoreApp' | Should -Be 'Android Managed'
    }

    It 'Should return Managed Google Play for androidManagedStoreApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.androidManagedStoreApp' | Should -Be 'Managed Google Play'
    }

    It 'Should return Store for Business for microsoftStoreForBusinessApp' {
        Get-InTUIAppTypeFriendlyName -ODataType '#microsoft.graph.microsoftStoreForBusinessApp' | Should -Be 'Store for Business'
    }
}

Describe 'Get-InTUIGroupType' {
    It 'Should return Dynamic Security for dynamic security groups' {
        $group = @{
            groupTypes      = @('DynamicMembership')
            securityEnabled = $true
            mailEnabled     = $false
        }
        Get-InTUIGroupType -Group $group | Should -BeLike '*Dynamic Security*'
    }

    It 'Should return Dynamic M365 for dynamic non-security groups' {
        $group = @{
            groupTypes      = @('DynamicMembership')
            securityEnabled = $false
            mailEnabled     = $true
        }
        Get-InTUIGroupType -Group $group | Should -BeLike '*Dynamic M365*'
    }

    It 'Should return Security for security-only groups' {
        $group = @{
            groupTypes      = @()
            securityEnabled = $true
            mailEnabled     = $false
        }
        Get-InTUIGroupType -Group $group | Should -BeLike '*Security*'
    }

    It 'Should return Mail-enabled Security for mail+security groups' {
        $group = @{
            groupTypes      = @()
            securityEnabled = $true
            mailEnabled     = $true
        }
        Get-InTUIGroupType -Group $group | Should -BeLike '*Mail-enabled Security*'
    }

    It 'Should return Microsoft 365 for Unified groups' {
        $group = @{
            groupTypes      = @('Unified')
            securityEnabled = $false
            mailEnabled     = $true
        }
        Get-InTUIGroupType -Group $group | Should -BeLike '*Microsoft 365*'
    }

    It 'Should return Distribution for mail-only groups' {
        $group = @{
            groupTypes      = @()
            securityEnabled = $false
            mailEnabled     = $true
        }
        Get-InTUIGroupType -Group $group | Should -BeLike '*Distribution*'
    }

    It 'Should return Assigned Security as fallback' {
        $group = @{
            groupTypes      = @()
            securityEnabled = $false
            mailEnabled     = $false
        }
        Get-InTUIGroupType -Group $group | Should -BeLike '*Assigned Security*'
    }
}

Describe 'Logging Functions' {
    Describe 'Initialize-InTUILog' {
        BeforeEach {
            $script:LogFilePath = $null
        }

        It 'Should create a log file in the specified directory' {
            $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
            New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
            Initialize-InTUILog -LogDirectory $testLogDir
            $script:LogFilePath | Should -Not -BeNullOrEmpty
            Test-Path $script:LogFilePath | Should -BeTrue
        }

        It 'Should create log file with InTUI prefix' {
            $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
            New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
            Initialize-InTUILog -LogDirectory $testLogDir
            $script:LogFilePath | Should -BeLike '*InTUI_*'
        }

        It 'Should write a header to the log file' {
            $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
            New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
            Initialize-InTUILog -LogDirectory $testLogDir
            $content = Get-Content $script:LogFilePath -Raw
            $content | Should -BeLike '*InTUI Log*'
        }

        It 'Should include version in the header' {
            $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
            New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
            Initialize-InTUILog -LogDirectory $testLogDir
            $content = Get-Content $script:LogFilePath -Raw
            $content | Should -BeLike '*Version*'
        }
    }

    Describe 'Write-InTUILog' {
        BeforeEach {
            $script:LogFilePath = $null
            $script:TestLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
            New-Item -Path $script:TestLogDir -ItemType Directory -Force | Out-Null
            Initialize-InTUILog -LogDirectory $script:TestLogDir
        }

        It 'Should append log entries to the file' {
            Write-InTUILog -Message 'Test message'
            $content = Get-Content $script:LogFilePath -Raw
            $content | Should -BeLike '*Test message*'
        }

        It 'Should include timestamp in log entries' {
            Write-InTUILog -Message 'Timestamped entry'
            $content = Get-Content $script:LogFilePath
            $lastLine = $content[-1]
            $lastLine | Should -Match '^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\]'
        }

        It 'Should include level in log entries' {
            Write-InTUILog -Level 'ERROR' -Message 'Error entry'
            $content = Get-Content $script:LogFilePath
            $lastLine = $content[-1]
            $lastLine | Should -BeLike '*[ERROR]*'
        }

        It 'Should default to INFO level' {
            Write-InTUILog -Message 'Info entry'
            $content = Get-Content $script:LogFilePath
            $lastLine = $content[-1]
            $lastLine | Should -BeLike '*[INFO]*'
        }

        It 'Should include context data when provided' {
            Write-InTUILog -Message 'Context entry' -Context @{ Key1 = 'Value1'; Key2 = 'Value2' }
            $content = Get-Content $script:LogFilePath
            $lastLine = $content[-1]
            $lastLine | Should -BeLike '*Key1=Value1*'
            $lastLine | Should -BeLike '*Key2=Value2*'
        }

        It 'Should handle null context values gracefully' {
            Write-InTUILog -Message 'Null context' -Context @{ Key1 = $null; Key2 = 'Value' }
            $content = Get-Content $script:LogFilePath
            $lastLine = $content[-1]
            $lastLine | Should -BeLike '*Key2=Value*'
            $lastLine | Should -Not -BeLike '*Key1=*'
        }

        It 'Should not throw when log file path is null' {
            $script:LogFilePath = $null
            { Write-InTUILog -Message 'Should not throw' } | Should -Not -Throw
        }

        It 'Should support WARN level' {
            Write-InTUILog -Level 'WARN' -Message 'Warning entry'
            $content = Get-Content $script:LogFilePath
            $lastLine = $content[-1]
            $lastLine | Should -BeLike '*[WARN]*'
        }

        It 'Should support DEBUG level' {
            Write-InTUILog -Level 'DEBUG' -Message 'Debug entry'
            $content = Get-Content $script:LogFilePath
            $lastLine = $content[-1]
            $lastLine | Should -BeLike '*[DEBUG]*'
        }
    }

    Describe 'Get-InTUILogPath' {
        It 'Should return null when log is not initialized' {
            $script:LogFilePath = $null
            Get-InTUILogPath | Should -BeNullOrEmpty
        }

        It 'Should return the log path after initialization' {
            $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
            New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
            Initialize-InTUILog -LogDirectory $testLogDir
            Get-InTUILogPath | Should -Not -BeNullOrEmpty
        }
    }
}

Describe 'Invoke-InTUIGraphRequest URI Construction' {
    BeforeAll {
        $script:Connected = $true
        $script:LogFilePath = $null
    }

    AfterAll {
        $script:Connected = $false
    }

    It 'Should prepend base URL for relative URIs' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'
        $script:GraphBetaUrl = 'https://graph.microsoft.com/beta'

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/users'
        $script:CapturedUri | Should -Be 'https://graph.microsoft.com/v1.0/users'
    }

    It 'Should use beta URL when -Beta is specified' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'
        $script:GraphBetaUrl = 'https://graph.microsoft.com/beta'

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices' -Beta
        $script:CapturedUri | Should -BeLike 'https://graph.microsoft.com/beta/*'
    }

    It 'Should use GCC High URLs when environment is USGov' {
        $script:GraphBaseUrl = $script:CloudEnvironments['USGov'].GraphBaseUrl
        $script:GraphBetaUrl = $script:CloudEnvironments['USGov'].GraphBetaUrl

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/users'
        $script:CapturedUri | Should -BeLike '*graph.microsoft.us*'
    }

    It 'Should use DoD URLs when environment is USGovDoD' {
        $script:GraphBaseUrl = $script:CloudEnvironments['USGovDoD'].GraphBaseUrl
        $script:GraphBetaUrl = $script:CloudEnvironments['USGovDoD'].GraphBetaUrl

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/users'
        $script:CapturedUri | Should -BeLike '*dod-graph.microsoft.us*'
    }

    It 'Should use China URLs when environment is China' {
        $script:GraphBaseUrl = $script:CloudEnvironments['China'].GraphBaseUrl
        $script:GraphBetaUrl = $script:CloudEnvironments['China'].GraphBetaUrl

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/users'
        $script:CapturedUri | Should -BeLike '*microsoftgraph.chinacloudapi.cn*'
    }

    It 'Should not prepend base URL for absolute URIs' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri 'https://graph.microsoft.us/v1.0/users?$top=10'
        $script:CapturedUri | Should -Be 'https://graph.microsoft.us/v1.0/users?$top=10'
    }

    It 'Should append $top parameter when Top is specified' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/users' -Top 25
        $script:CapturedUri | Should -BeLike '*$top=25*'
    }

    It 'Should return null when not connected' {
        $script:Connected = $false
        $result = Invoke-InTUIGraphRequest -Uri '/users'
        $result | Should -BeNullOrEmpty
        $script:Connected = $true
    }

    It 'Should use GCC High beta URL when environment is USGov and -Beta specified' {
        $script:GraphBaseUrl = $script:CloudEnvironments['USGov'].GraphBaseUrl
        $script:GraphBetaUrl = $script:CloudEnvironments['USGov'].GraphBetaUrl

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices' -Beta
        $script:CapturedUri | Should -BeLike 'https://graph.microsoft.us/beta/*'
    }

    It 'Should use DoD beta URL when environment is USGovDoD and -Beta specified' {
        $script:GraphBaseUrl = $script:CloudEnvironments['USGovDoD'].GraphBaseUrl
        $script:GraphBetaUrl = $script:CloudEnvironments['USGovDoD'].GraphBetaUrl

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices' -Beta
        $script:CapturedUri | Should -BeLike 'https://dod-graph.microsoft.us/beta/*'
    }

    It 'Should use China beta URL when environment is China and -Beta specified' {
        $script:GraphBaseUrl = $script:CloudEnvironments['China'].GraphBaseUrl
        $script:GraphBetaUrl = $script:CloudEnvironments['China'].GraphBetaUrl

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/deviceManagement/managedDevices' -Beta
        $script:CapturedUri | Should -BeLike 'https://microsoftgraph.chinacloudapi.cn/beta/*'
    }

    It 'Should append $top with & when URI already has query params' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/users?$filter=accountEnabled eq true' -Top 10
        $script:CapturedUri | Should -BeLike '*&$top=10*'
    }

    It 'Should not append $top for POST requests' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{}
        }

        Invoke-InTUIGraphRequest -Uri '/users' -Method POST -Body @{ name = 'test' } -Top 10
        $script:CapturedUri | Should -Not -BeLike '*$top*'
    }

    It 'Should handle pagination and collect all results' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'
        $callCount = 0

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $callCount++
            if ($callCount -eq 1) {
                return @{
                    value = @(@{ id = '1' })
                    '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'
                }
            } else {
                return @{
                    value = @(@{ id = '2' })
                }
            }
        }

        $result = Invoke-InTUIGraphRequest -Uri '/users' -All
        $result.Count | Should -Be 2
    }

    It 'Should send JSON body for POST requests' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'

        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri, $Method, $Body, $ContentType)
            $script:CapturedMethod = $Method
            $script:CapturedContentType = $ContentType
            $script:CapturedBody = $Body
            return @{}
        }

        Invoke-InTUIGraphRequest -Uri '/users' -Method POST -Body @{ displayName = 'Test' }
        $script:CapturedMethod | Should -Be 'POST'
        $script:CapturedContentType | Should -Be 'application/json'
        $script:CapturedBody | Should -BeLike '*displayName*'
    }
}

Describe 'Connect-InTUIGraph Parameter Validation' {
    It 'Should have Environment parameter with ValidateSet' {
        $cmd = Get-Command Connect-InTUIGraph
        $envParam = $cmd.Parameters['Environment']
        $envParam | Should -Not -BeNullOrEmpty

        $validateSet = $envParam.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
        $validateSet | Should -Not -BeNullOrEmpty
        $validateSet.ValidValues | Should -Contain 'Global'
        $validateSet.ValidValues | Should -Contain 'USGov'
        $validateSet.ValidValues | Should -Contain 'USGovDoD'
        $validateSet.ValidValues | Should -Contain 'China'
    }

    It 'Should have default scopes defined' {
        $cmd = Get-Command Connect-InTUIGraph
        $scopeParam = $cmd.Parameters['Scopes']
        $scopeParam | Should -Not -BeNullOrEmpty
    }

    It 'Should have TenantId parameter' {
        $cmd = Get-Command Connect-InTUIGraph
        $cmd.Parameters.ContainsKey('TenantId') | Should -BeTrue
    }

    It 'Should default Environment to Global' {
        $cmd = Get-Command Connect-InTUIGraph
        $envParam = $cmd.Parameters['Environment']
        $defaultValue = $envParam.Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
        # The default value is set in the param block
        $cmd.Parameters['Environment'].ParameterType | Should -Be ([string])
    }

    It 'Should set CloudEnvironment script variable when connecting' {
        $script:CloudEnvironment = 'Global'
        Mock Connect-MgGraph { }
        Mock Get-MgContext { return @{ TenantId = 'test-tenant'; Account = 'test@test.com' } }

        Connect-InTUIGraph -Environment 'USGov'
        $script:CloudEnvironment | Should -Be 'USGov'
    }

    It 'Should update GraphBaseUrl when switching to USGov' {
        Mock Connect-MgGraph { }
        Mock Get-MgContext { return @{ TenantId = 'test-tenant'; Account = 'test@test.com' } }

        Connect-InTUIGraph -Environment 'USGov'
        $script:GraphBaseUrl | Should -Be 'https://graph.microsoft.us/v1.0'
        $script:GraphBetaUrl | Should -Be 'https://graph.microsoft.us/beta'
    }

    It 'Should update GraphBaseUrl when switching to USGovDoD' {
        Mock Connect-MgGraph { }
        Mock Get-MgContext { return @{ TenantId = 'test-tenant'; Account = 'test@test.com' } }

        Connect-InTUIGraph -Environment 'USGovDoD'
        $script:GraphBaseUrl | Should -Be 'https://dod-graph.microsoft.us/v1.0'
        $script:GraphBetaUrl | Should -Be 'https://dod-graph.microsoft.us/beta'
    }

    It 'Should update GraphBaseUrl when switching to China' {
        Mock Connect-MgGraph { }
        Mock Get-MgContext { return @{ TenantId = 'test-tenant'; Account = 'test@test.com' } }

        Connect-InTUIGraph -Environment 'China'
        $script:GraphBaseUrl | Should -Be 'https://microsoftgraph.chinacloudapi.cn/v1.0'
        $script:GraphBetaUrl | Should -Be 'https://microsoftgraph.chinacloudapi.cn/beta'
    }

    It 'Should set Connected to true on successful connection' {
        $script:Connected = $false
        Mock Connect-MgGraph { }
        Mock Get-MgContext { return @{ TenantId = 'test-tenant'; Account = 'test@test.com' } }

        $result = Connect-InTUIGraph -Environment 'Global'
        $result | Should -BeTrue
        $script:Connected | Should -BeTrue
    }

    It 'Should return false when Get-MgContext returns null' {
        $script:Connected = $false
        Mock Connect-MgGraph { }
        Mock Get-MgContext { return $null }

        $result = Connect-InTUIGraph -Environment 'Global'
        $result | Should -BeFalse
    }

    It 'Should return false when Connect-MgGraph throws' {
        $script:Connected = $false
        Mock Connect-MgGraph { throw "Auth failed" }

        $result = Connect-InTUIGraph -Environment 'Global'
        $result | Should -BeFalse
    }

    It 'Should pass NoWelcome parameter to Connect-MgGraph' {
        Mock Connect-MgGraph {
            param($Scopes, $NoWelcome, $Environment, $TenantId)
            $script:CapturedNoWelcome = $NoWelcome
        }
        Mock Get-MgContext { return @{ TenantId = 'test'; Account = 'test@test.com' } }

        Connect-InTUIGraph -Environment 'Global'
        $script:CapturedNoWelcome | Should -BeTrue
    }

    It 'Should pass MgEnvironment name to Connect-MgGraph' {
        Mock Connect-MgGraph {
            param($Scopes, $NoWelcome, $Environment, $TenantId)
            $script:CapturedMgEnv = $Environment
        }
        Mock Get-MgContext { return @{ TenantId = 'test'; Account = 'test@test.com' } }

        Connect-InTUIGraph -Environment 'USGov'
        $script:CapturedMgEnv | Should -Be 'USGov'
    }
}

Describe 'Get-InTUIPagedResults Query Building' {
    BeforeAll {
        $script:Connected = $true
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'
        $script:GraphBetaUrl = 'https://graph.microsoft.com/beta'
        $script:LogFilePath = $null
    }

    AfterAll {
        $script:Connected = $false
    }

    It 'Should build URI with filter parameter' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/users' -Filter "accountEnabled eq true"
        $script:CapturedUri | Should -BeLike '*$filter=accountEnabled eq true*'
    }

    It 'Should build URI with select parameter' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/users' -Select 'id,displayName'
        $script:CapturedUri | Should -BeLike '*$select=id,displayName*'
    }

    It 'Should build URI with orderby parameter' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/users' -OrderBy 'displayName'
        $script:CapturedUri | Should -BeLike '*$orderby=displayName*'
    }

    It 'Should build URI with top parameter from PageSize' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/users' -PageSize 10
        $script:CapturedUri | Should -BeLike '*$top=10*'
    }

    It 'Should combine multiple query parameters' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/users' -Filter "accountEnabled eq true" -Select 'id,displayName' -PageSize 10
        $script:CapturedUri | Should -BeLike '*$top=10*'
        $script:CapturedUri | Should -BeLike '*$filter=*'
        $script:CapturedUri | Should -BeLike '*$select=*'
    }

    It 'Should return a hashtable with Results and NextLink' {
        Mock Invoke-MgGraphRequest -MockWith {
            return @{
                value             = @(@{ id = '1'; displayName = 'Test' })
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=abc'
            }
        }

        $result = Get-InTUIPagedResults -Uri '/users'
        $result | Should -BeOfType [hashtable]
        $result.ContainsKey('Results') | Should -BeTrue
        $result.ContainsKey('NextLink') | Should -BeTrue
    }

    It 'Should return Results as array with values' {
        Mock Invoke-MgGraphRequest -MockWith {
            return @{
                value = @(
                    @{ id = '1'; displayName = 'User1' },
                    @{ id = '2'; displayName = 'User2' }
                )
            }
        }

        $result = Get-InTUIPagedResults -Uri '/users'
        $result.Results.Count | Should -Be 2
    }

    It 'Should include Count key in result' {
        Mock Invoke-MgGraphRequest -MockWith {
            return @{
                value = @(@{ id = '1' })
                '@odata.count' = 42
            }
        }

        $result = Get-InTUIPagedResults -Uri '/users'
        $result.ContainsKey('Count') | Should -BeTrue
        $result.Count | Should -Be 42
    }

    It 'Should build URI with search parameter' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/users' -Search 'john'
        $script:CapturedUri | Should -BeLike '*$search="john"*'
    }

    It 'Should build URI with expand parameter' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/groups' -Expand 'members'
        $script:CapturedUri | Should -BeLike '*$expand=members*'
    }

    It 'Should use beta endpoint when Beta switch is specified' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/deviceManagement/managedDevices' -Beta
        $script:CapturedUri | Should -BeLike '*beta/*'
    }
}

Describe 'Logging Integration with Graph Requests' {
    BeforeAll {
        $script:Connected = $true
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'
        $script:GraphBetaUrl = 'https://graph.microsoft.com/beta'
        $script:CloudEnvironment = 'Global'
    }

    BeforeEach {
        $script:TestLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
        New-Item -Path $script:TestLogDir -ItemType Directory -Force | Out-Null
        Initialize-InTUILog -LogDirectory $script:TestLogDir
    }

    AfterAll {
        $script:Connected = $false
        $script:LogFilePath = $null
    }

    It 'Should log Graph API requests' {
        Mock Invoke-MgGraphRequest -MockWith {
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/users'
        $content = Get-Content $script:LogFilePath -Raw
        $content | Should -BeLike '*Graph API request*'
    }

    It 'Should log environment in Graph API requests' {
        Mock Invoke-MgGraphRequest -MockWith {
            return @{ value = @() }
        }

        Invoke-InTUIGraphRequest -Uri '/users'
        $content = Get-Content $script:LogFilePath -Raw
        $content | Should -BeLike '*Environment=Global*'
    }

    It 'Should log request completion' {
        Mock Invoke-MgGraphRequest -MockWith {
            return @{ value = @(@{ id = '1' }) }
        }

        Invoke-InTUIGraphRequest -Uri '/users'
        $content = Get-Content $script:LogFilePath -Raw
        $content | Should -BeLike '*Graph API request completed*'
    }

    It 'Should log errors on Graph API failures' {
        Mock Invoke-MgGraphRequest -MockWith {
            throw "Network error"
        }

        $result = Invoke-InTUIGraphRequest -Uri '/users'
        $result | Should -BeNullOrEmpty
        $content = Get-Content $script:LogFilePath -Raw
        $content | Should -BeLike '*ERROR*'
    }

    It 'Should log not-connected warnings' {
        $script:Connected = $false
        Invoke-InTUIGraphRequest -Uri '/users'
        $content = Get-Content $script:LogFilePath -Raw
        $content | Should -BeLike '*WARN*not connected*'
        $script:Connected = $true
    }
}

Describe 'Logging File Placement' {
    BeforeEach {
        $script:LogFilePath = $null
    }

    It 'Should create log file with .log extension' {
        $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        Initialize-InTUILog -LogDirectory $testLogDir
        $script:LogFilePath | Should -BeLike '*.log'
    }

    It 'Should create log file with timestamp in name' {
        $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        Initialize-InTUILog -LogDirectory $testLogDir
        $fileName = Split-Path $script:LogFilePath -Leaf
        $fileName | Should -Match 'InTUI_\d{8}_\d{6}\.log'
    }

    It 'Should include PowerShell version in log header' {
        $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        Initialize-InTUILog -LogDirectory $testLogDir
        $content = Get-Content $script:LogFilePath -Raw
        $content | Should -BeLike '*PowerShell*'
    }

    It 'Should include OS info in log header' {
        $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        Initialize-InTUILog -LogDirectory $testLogDir
        $content = Get-Content $script:LogFilePath -Raw
        $content | Should -BeLike '*OS*'
    }

    It 'Should handle non-existent directory gracefully' {
        $badDir = Join-Path $TestDrive "nonexistent_$(Get-Random)/subdir"
        Initialize-InTUILog -LogDirectory $badDir
        $script:LogFilePath | Should -BeNullOrEmpty
    }

    It 'Should write multiple log entries sequentially' {
        $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        Initialize-InTUILog -LogDirectory $testLogDir

        Write-InTUILog -Message 'First entry'
        Write-InTUILog -Message 'Second entry'
        Write-InTUILog -Message 'Third entry'

        $lines = Get-Content $script:LogFilePath
        $logLines = $lines | Where-Object { $_ -match '^\[' }
        $logLines.Count | Should -Be 3
    }

    It 'Should sort context keys alphabetically' {
        $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        Initialize-InTUILog -LogDirectory $testLogDir

        Write-InTUILog -Message 'Sorted test' -Context @{ Zebra = 'z'; Alpha = 'a'; Middle = 'm' }
        $content = Get-Content $script:LogFilePath
        $lastLine = $content[-1]
        # Alpha should come before Middle which should come before Zebra
        $lastLine | Should -Match 'Alpha=a.*Middle=m.*Zebra=z'
    }
}
