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
    $script:InTUIVersion = '1.0.1'
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
    function Invoke-MgGraphRequest {
        param($Uri, $Method, $OutputType, $Body, $ContentType)
        return @{ value = @() }
    }
    function Connect-MgGraph { param($Scopes, $NoWelcome, $Environment, $TenantId) }
    function Get-MgContext { return $null }

    # Dot-source the files under test
    . "$ProjectRoot/Private/AnsiPalette.ps1"
    . "$ProjectRoot/Private/AnsiGradient.ps1"
    . "$ProjectRoot/Private/AnsiWidth.ps1"
    . "$ProjectRoot/Private/AnsiCapability.ps1"
    . "$ProjectRoot/Private/RenderPanel.ps1"
    . "$ProjectRoot/Private/Logging.ps1"
    . "$ProjectRoot/Private/UIHelpers.ps1"
    . "$ProjectRoot/Private/InputPrompt.ps1"
    . "$ProjectRoot/Private/MenuArrowMulti.ps1"
    . "$ProjectRoot/Private/GraphHelpers.ps1"
    . "$ProjectRoot/Private/ReportHelpers.ps1"
    . "$ProjectRoot/Private/AppIntentHelpers.ps1"
    . "$ProjectRoot/Private/PimRoleActivation.ps1"
    . "$ProjectRoot/Private/GlobalSearch.ps1"

    # Functions from Views that contain pure logic
    . "$ProjectRoot/Views/Apps.ps1"
    . "$ProjectRoot/Views/CompliancePolicies.ps1"
    . "$ProjectRoot/Views/ConditionalAccess.ps1"
    . "$ProjectRoot/Views/Dashboard.ps1"
    . "$ProjectRoot/Views/Enrollment.ps1"
    . "$ProjectRoot/Views/Groups.ps1"
    . "$ProjectRoot/Views/Security.ps1"
}

Describe 'App Intent Response Conversion' {
    It 'Should extract apps from a device-specific mobileAppIntentAndState entity' {
        $response = [pscustomobject]@{
            id                      = 'intent-state-1'
            managedDeviceIdentifier = 'device-1'
            userId                  = 'user-1'
            mobileAppList           = @(
                [pscustomobject]@{
                    displayName     = 'Google Chrome'
                    installState    = 'installed'
                    mobileAppIntent = 'available'
                }
            )
        }

        $result = Get-InTUIAppIntentMobileApp -Response $response

        $result | Should -HaveCount 1
        $result[0].displayName | Should -Be 'Google Chrome'
        $result[0].installState | Should -Be 'installed'
        $result[0].mobileAppIntent | Should -Be 'available'
    }

    It 'Should extract apps from raw JSON mobileAppIntentAndState entity responses' {
        $response = @'
{
  "id": "intent-state-1",
  "mobileAppList": [
    {
      "displayName": "Google Chrome",
      "installState": "installed",
      "mobileAppIntent": "available"
    }
  ],
  "managedDeviceIdentifier": "device-1",
  "userId": "user-1"
}
'@

        $result = Get-InTUIAppIntentMobileApp -Response $response

        $result | Should -HaveCount 1
        $result[0].displayName | Should -Be 'Google Chrome'
    }

    It 'Should extract apps from mobileAppIntentAndStates collection responses' {
        $response = [pscustomobject]@{
            value = @(
                [pscustomobject]@{
                    mobileAppList = @(
                        [pscustomobject]@{ displayName = 'Company Portal'; installState = 'installed'; mobileAppIntent = 'required' }
                    )
                }
            )
        }

        $result = Get-InTUIAppIntentMobileApp -Response $response

        $result | Should -HaveCount 1
        $result[0].displayName | Should -Be 'Company Portal'
    }
}

Describe 'Intune Report Response Conversion' {
    BeforeAll {
        $defaultFields = @('IntuneDeviceId', 'PolicyBaseTypeName', 'PolicyId', 'PolicyStatus', 'UPN', 'UserId', 'PspdpuLastModifiedTimeUtc', 'PolicyName', 'UnifiedPolicyType')
    }

    It 'Should map report Values using Schema field names' {
        $response = [pscustomobject]@{
            Schema = @(
                [pscustomobject]@{ Column = 'PolicyName' }
                [pscustomobject]@{ Column = 'PolicyStatus' }
                [pscustomobject]@{ Column = 'UnifiedPolicyType' }
            )
            Values = @(
                , @('Baseline [Prod]', 'Succeeded', 'Settings Catalog')
            )
        }

        $result = ConvertFrom-InTUIReportResponse -Response $response -DefaultFields $defaultFields

        $result | Should -HaveCount 1
        $result[0].PolicyName | Should -Be 'Baseline [Prod]'
        $result[0].PolicyStatus | Should -Be 'Succeeded'
        $result[0].UnifiedPolicyType | Should -Be 'Settings Catalog'
    }

    It 'Should map report rows using default fields when Schema is absent' {
        $response = [pscustomobject]@{
            rows = @(
                , @('device-1', 'DeviceManagementConfigurationPolicy', 'policy-1', 'Succeeded', 'user@example.com', 'user-1', '2026-05-05T00:00:00Z', 'Modern Policy', 'Settings Catalog')
            )
        }

        $result = ConvertFrom-InTUIReportResponse -Response $response -DefaultFields $defaultFields

        $result | Should -HaveCount 1
        $result[0].PolicyName | Should -Be 'Modern Policy'
        $result[0].UPN | Should -Be 'user@example.com'
    }

    It 'Should parse raw JSON report responses from Graph report actions' {
        $response = @'
{
  "TotalRowCount": 1,
  "Schema": [
    { "Column": "IntuneDeviceId", "PropertyType": "String" },
    { "Column": "PolicyBaseTypeName", "PropertyType": "String" },
    { "Column": "PolicyId", "PropertyType": "String" },
    { "Column": "PolicyName", "PropertyType": "String" },
    { "Column": "PolicyStatus", "PropertyType": "Int32" },
    { "Column": "PspdpuLastModifiedTimeUtc", "PropertyType": "DateTime" },
    { "Column": "UnifiedPolicyType", "PropertyType": "String" },
    { "Column": "UnifiedPolicyType_loc", "PropertyType": "String" },
    { "Column": "UPN", "PropertyType": "String" },
    { "Column": "UserId", "PropertyType": "String" }
  ],
  "Values": [
    [
      "device-1",
      "DeviceManagementConfigurationPolicy",
      "policy-1",
      "[IHD] CISv4 - WIN - L2 - Turn off the Store application",
      2,
      "2026-05-02T20:58:48",
      "SettingsCatalog",
      "Settings Catalog",
      "user@example.com",
      "user-1"
    ]
  ]
}
'@

        $result = ConvertFrom-InTUIReportResponse -Response $response -DefaultFields $defaultFields

        $result | Should -HaveCount 1
        $result[0].PolicyName | Should -Be '[IHD] CISv4 - WIN - L2 - Turn off the Store application'
        $result[0].PolicyStatus | Should -Be 2
        $result[0].UPN | Should -Be 'user@example.com'
    }

    It 'Should convert numeric Intune report policy status codes' {
        ConvertTo-InTUIReportPolicyStatus -Status 1 | Should -Be 'NotApplicable'
        ConvertTo-InTUIReportPolicyStatus -Status 2 | Should -Be 'Succeeded'
        ConvertTo-InTUIReportPolicyStatus -Status 3 | Should -Be 'Failed'
        ConvertTo-InTUIReportPolicyStatus -Status 4 | Should -Be 'Conflict'
    }
}

Describe 'App Install Status Retrieval' {
    BeforeAll {
        $script:Connected = $true
    }

    It 'Should build device install statuses without using unsupported mobileApps deviceStatuses route' {
        Mock Get-InTUIPagedResults -MockWith {
            return @{
                Results = @(
                    [pscustomobject]@{
                        id                 = 'device-1'
                        deviceName         = 'WIN-01'
                        userId             = 'user-1'
                        userPrincipalName  = 'user@example.com'
                        osVersion          = '10.0.26100'
                        lastSyncDateTime   = '2026-05-06T12:00:00Z'
                    }
                )
                TotalCount = 1
            }
        }

        Mock Invoke-InTUIGraphRequest -MockWith {
            param([string]$Uri)
            $script:CapturedAppStatusUris += $Uri
            return [pscustomobject]@{
                mobileAppList = @(
                    [pscustomobject]@{
                        applicationId = 'app-1'
                        displayName   = 'Google Chrome'
                        installState  = 'installed'
                    }
                )
            }
        }

        $script:CapturedAppStatusUris = @()

        $result = Get-InTUIAppDeviceInstallStatus -AppId 'app-1' -AppName 'Google Chrome'

        $result | Should -HaveCount 1
        $result[0].deviceName | Should -Be 'WIN-01'
        $result[0].installState | Should -Be 'installed'
        $script:CapturedAppStatusUris | Should -Not -Contain '/deviceAppManagement/mobileApps/app-1/deviceStatuses'
        $script:CapturedAppStatusUris[0] | Should -Be "/users('user-1')/mobileAppIntentAndStates('device-1')"
    }

    It 'Should retrieve user install statuses through the Intune report action' {
        Mock Invoke-InTUIGraphRequest -MockWith {
            param([string]$Uri, [string]$Method, [hashtable]$Body)
            $script:CapturedUserStatusUri = $Uri
            $script:CapturedUserStatusMethod = $Method
            $script:CapturedUserStatusBody = $Body
            return [pscustomobject]@{
                Schema = @(
                    [pscustomobject]@{ Column = 'UserId' }
                    [pscustomobject]@{ Column = 'ApplicationId' }
                    [pscustomobject]@{ Column = 'UserName' }
                    [pscustomobject]@{ Column = 'UserPrincipalName' }
                    [pscustomobject]@{ Column = 'InstalledCount' }
                    [pscustomobject]@{ Column = 'FailedCount' }
                    [pscustomobject]@{ Column = 'PendingInstallCount' }
                    [pscustomobject]@{ Column = 'NotApplicableCount' }
                    [pscustomobject]@{ Column = 'NotInstalledCount' }
                )
                Values = @(
                    , @('user-1', 'app-1', 'Test User', 'user@example.com', 1, 0, 0, 0, 2)
                )
            }
        }

        $result = Get-InTUIAppUserInstallStatus -AppId 'app-1'

        $result | Should -HaveCount 1
        $result[0].UserPrincipalName | Should -Be 'user@example.com'
        $result[0].InstalledCount | Should -Be 1
        $script:CapturedUserStatusUri | Should -Be '/deviceManagement/reports/getUserInstallStatusReport'
        $script:CapturedUserStatusMethod | Should -Be 'POST'
        $script:CapturedUserStatusBody.filter | Should -Be "(ApplicationId eq 'app-1')"
    }
}

Describe 'Show-InTUIMultiSelect' {
    BeforeEach {
        $script:HasArrowKeySupport = $true
    }

    It 'Should return the first choice when the arrow menu returns index zero' {
        Mock Show-InTUIMenuArrowMulti -MockWith { return 0 }

        $result = @(Show-InTUIMultiSelect -Title 'Select platforms' -Choices @('Windows', 'macOS'))

        $result | Should -HaveCount 1
        $result[0] | Should -Be 'Windows'
    }

    It 'Should return each selected choice as a separate pipeline item' {
        Mock Show-InTUIMenuArrowMulti { return @(0, 2) }

        $result = @(Show-InTUIMultiSelect -Title 'Select platforms' -Choices @('Windows', 'macOS', 'iOS'))

        $result | Should -HaveCount 2
        $result[0] | Should -Be 'Windows'
        $result[1] | Should -Be 'iOS'
    }
}

Describe 'Show-InTUIHeader' {
    BeforeEach {
        $script:HeaderOutput = @()
        Mock Write-Host -MockWith {
            param($Object)
            $script:HeaderOutput += [string]$Object
        }
    }

    It 'Should support compact rendering for the dashboard shell' {
        Show-InTUIHeader

        $script:HeaderOutput[0] | Should -Match ([regex]::Escape([string][char]0x2500))
        $script:HeaderOutput -join "`n" | Should -Match 'Intune Terminal User Interface'

        $script:HeaderOutput = @()
        Show-InTUIHeader -Compact

        $script:HeaderOutput | Should -Not -Contain ''
    }

    It 'Should render when console width resolves to zero' {
        Mock Resolve-InTUIConsoleWindowWidth -MockWith { return 0 }

        { Show-InTUIHeader -Compact } | Should -Not -Throw
        $script:HeaderOutput[0] | Should -Match ([regex]::Escape([string][char]0x2500))
    }
}

Describe 'Resolve-InTUIConsoleWindowWidth' {
    It 'Should use default width for non-interactive zero-width consoles' {
        Resolve-InTUIConsoleWindowWidth -Width 0 | Should -Be 80
    }

    It 'Should preserve valid console widths' {
        Resolve-InTUIConsoleWindowWidth -Width 120 | Should -Be 120
    }
}

Describe 'Strip-InTUIMarkup' {
    It 'Should remove leftover nested style tags from menu labels' {
        $label = '[grey]DC[/] [white]DC [[white]] Win - OIB[/] [grey]| Windows[/]'

        Strip-InTUIMarkup -Text $label | Should -Be 'DC DC Win - OIB | Windows'
    }

    It 'Should preserve ordinary bracketed title text' {
        $label = '[white]Baseline [[Prod]][/] [grey]| Windows[/]'

        Strip-InTUIMarkup -Text $label | Should -Be 'Baseline [Prod] | Windows'
    }
}

Describe 'Split-InTUIPlainTextByDisplayWidth' {
    It 'Should return an empty segment for empty text' {
        $result = @(Split-InTUIPlainTextByDisplayWidth -Text '' -Width 10)

        $result | Should -HaveCount 1
        $result[0] | Should -Be ''
    }

    It 'Should leave text unchanged when it already fits' {
        $result = @(Split-InTUIPlainTextByDisplayWidth -Text 'short text' -Width 20)

        $result | Should -HaveCount 1
        $result[0] | Should -Be 'short text'
    }

    It 'Should prefer wrapping at word boundaries' {
        $result = Split-InTUIPlainTextByDisplayWidth -Text 'alpha beta gamma delta' -Width 12

        $result | Should -HaveCount 2
        $result[0] | Should -Be 'alpha beta'
        $result[1] | Should -Be 'gamma delta'
    }

    It 'Should split long tokens that have no spaces' {
        $result = Split-InTUIPlainTextByDisplayWidth -Text 'abcdefghijklmnop' -Width 6

        $result | Should -HaveCount 3
        $result[0] | Should -Be 'abcdef'
        $result[1] | Should -Be 'ghijkl'
        $result[2] | Should -Be 'mnop'
    }

    It 'Should respect display width for wide characters' {
        $result = Split-InTUIPlainTextByDisplayWidth -Text 'VM あいう Device' -Width 7

        foreach ($line in $result) {
            Measure-InTUIDisplayWidth -Text $line | Should -BeLessOrEqual 7
        }
    }
}

Describe 'Split-InTUIPanelContentLine' {
    It 'Should return one line with display width when content fits' {
        $result = Split-InTUIPanelContentLine -Line '[cyan]Short rule[/]' -Width 20
        $plainText = $result[0].Text -replace "`e\[[0-9;]*m", ''

        $result | Should -HaveCount 1
        $plainText | Should -Be 'Short rule'
        $result[0].DisplayWidth | Should -Be 10
    }

    It 'Should wrap long dynamic membership rules instead of truncating them' {
        $rule = '(device.deviceModel -contains "Virtual") or (device.deviceModel -contains "Cloud PC") or (device.deviceManufacturer -contains "VMware")'

        $result = Split-InTUIPanelContentLine -Line "[cyan]$rule[/]" -Width 48

        $plainLines = $result | ForEach-Object { $_.Text -replace "`e\[[0-9;]*m", '' }
        $plainText = $plainLines -join ' '

        $plainText | Should -Be $rule
        $plainText | Should -Not -Match '\.\.\.'
        @($result).Count | Should -BeGreaterThan 1
        foreach ($line in $result) {
            $line.DisplayWidth | Should -BeLessOrEqual 48
        }
    }

    It 'Should preserve a single enclosing style across wrapped lines' {
        $result = Split-InTUIPanelContentLine -Line '[cyan]alpha beta gamma delta[/]' -Width 10
        $plainLines = $result | ForEach-Object { $_.Text -replace "`e\[[0-9;]*m", '' }

        $plainLines | Should -HaveCount 3
        $plainLines[0] | Should -Be 'alpha beta'
        $plainLines[1] | Should -Be 'gamma'
        $plainLines[2] | Should -Be 'delta'
        foreach ($line in $result) {
            $line.DisplayWidth | Should -BeLessOrEqual 10
        }
    }
}

Describe 'Render-InTUIPanel' {
    BeforeEach {
        $script:PanelOutput = @()
        Mock Get-InTUIConsoleInnerWidth -MockWith { return 28 }
        Mock Write-Host -MockWith {
            param($Object)
            $script:PanelOutput += $Object
        }
    }

    It 'Should render long content on multiple panel rows without ellipsis' {
        Render-InTUIPanel -Title 'Rule' -Content '[cyan]alpha beta gamma delta epsilon zeta[/]' -BorderColor Cyan

        $contentRows = $script:PanelOutput | Where-Object { $_ -match 'alpha|gamma|epsilon' }
        $joinedOutput = $script:PanelOutput -join "`n"

        @($contentRows).Count | Should -BeGreaterThan 1
        $joinedOutput | Should -Match 'alpha'
        $joinedOutput | Should -Match 'zeta'
        $joinedOutput | Should -Not -Match '\.\.\.'
    }
}

Describe 'Dashboard Overview Content' {
    It 'Should consolidate inventory and compliance summaries into one content block' {
        $dashboardData = @{
            DeviceCount       = 3
            AppCount          = 2
            UserCount         = 3
            GroupCount        = 59
            CompliantCount    = 1
            NoncompliantCount = 2
            InGracePeriod     = 0
            ErrorCount        = 0
        }

        $content = New-InTUIDashboardOverviewContent -DashboardData $dashboardData -CompliancePercent 33.3 -ComplianceBar '[green]====[/]'

        $content | Should -Match '\[bold\]Inventory\[/\]'
        $content | Should -Match '\[white\]3\[/\] devices'
        $content | Should -Match '\[white\]2\[/\] apps'
        $content | Should -Match '\[white\]3\[/\] users'
        $content | Should -Match '\[white\]59\[/\] groups'
        $content | Should -Match '\[bold\]Compliance Status\[/\]'
        $content | Should -Match '33\.3%'
        $content | Should -Not -Match 'Managed apps across all platforms'
        $content | Should -Not -Match 'Azure AD directory users'
        $content | Should -Not -Match 'Security and distribution groups'
        ($content -split "`n")[0] | Should -Match '\[bold\]Inventory\[/\]'
        ($content -split "`n")[-1] | Should -Match '\[red\]x\[/\] Error'
    }

    It 'Should clear the loading spinner before rendering the dashboard panel' {
        $script:DashboardLoadingClearOnComplete = $false
        Mock Show-InTUILoading -MockWith {
            param($Title, $ScriptBlock, [switch]$ClearOnComplete)
            $script:DashboardLoadingClearOnComplete = $ClearOnComplete.IsPresent
            return @{
                DeviceCount       = 3
                AppCount          = 2
                UserCount         = 3
                GroupCount        = 59
                CompliantCount    = 1
                NoncompliantCount = 2
                InGracePeriod     = 0
                ErrorCount        = 0
            }
        }
        Mock Show-InTUIPanel -MockWith { }

        Show-InTUIDashboard

        $script:DashboardLoadingClearOnComplete | Should -BeTrue
    }
}

Describe 'Global Search Layout' {
    BeforeEach {
        $script:GlobalSearchHeaderCompact = $false
        $script:GlobalSearchLoadingClearOnComplete = $false
        $script:GlobalSearchInputCalls = 0
        Mock Clear-Host -MockWith { }
        Mock Show-InTUIHeader -MockWith {
            param($Subtitle, [switch]$Compact)
            $script:GlobalSearchHeaderCompact = $script:GlobalSearchHeaderCompact -or $Compact.IsPresent
        }
        Mock Show-InTUIBreadcrumb -MockWith { }
        Mock Write-InTUIText -MockWith { }
        Mock Show-InTUIWarning -MockWith { }
        Mock Read-InTUIKey -MockWith { }
        Mock Show-InTUILoading -MockWith {
            param($Title, $ScriptBlock, [switch]$ClearOnComplete)
            $script:GlobalSearchLoadingClearOnComplete = $ClearOnComplete.IsPresent
            return @{
                Devices = @()
                Apps    = @()
                Users   = @()
                Groups  = @()
            }
        }
    }

    It 'Should use compact header spacing and clear loading status rows' {
        Mock Read-InTUITextInput -MockWith {
            $script:GlobalSearchInputCalls++
            if ($script:GlobalSearchInputCalls -eq 1) { return 'entra' }
            return ''
        }

        Invoke-InTUIGlobalSearch

        $script:GlobalSearchHeaderCompact | Should -BeTrue
        $script:GlobalSearchLoadingClearOnComplete | Should -BeTrue
    }
}

Describe 'Mobile App Assignment Request Body' {
    BeforeAll {
        $script:Connected = $true
    }

    It 'Should preserve existing assignments when adding a new assignment' {
        Mock Invoke-InTUIGraphRequest -MockWith {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        id       = 'assignment-1'
                        intent   = 'available'
                        target   = [pscustomobject]@{
                            '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                        }
                        settings = [pscustomobject]@{
                            '@odata.type'                  = '#microsoft.graph.win32LobAppAssignmentSettings'
                            notifications                  = 'showAll'
                            installTimeSettings            = $null
                            restartSettings                = $null
                            deliveryOptimizationPriority   = 'foreground'
                        }
                        source   = 'direct'
                        sourceId = 'source-1'
                    }
                )
            }
        }

        $newAssignment = @{
            '@odata.type' = '#microsoft.graph.mobileAppAssignment'
            intent        = 'available'
            target        = @{
                '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
            }
            settings      = $null
        }

        $body = New-InTUIMobileAppAssignmentRequestBody -AppId 'app-1' -Assignment $newAssignment

        $body.mobileAppAssignments | Should -HaveCount 2
        $body.mobileAppAssignments[0].target.'@odata.type' | Should -Be '#microsoft.graph.allLicensedUsersAssignmentTarget'
        $body.mobileAppAssignments[0].settings.notifications | Should -Be 'showAll'
        $body.mobileAppAssignments[0].Contains('id') | Should -BeFalse
        $body.mobileAppAssignments[1].target.'@odata.type' | Should -Be '#microsoft.graph.allDevicesAssignmentTarget'
    }

    It 'Should not duplicate an existing assignment for the same target and intent' {
        Mock Invoke-InTUIGraphRequest -MockWith {
            return [pscustomobject]@{
                value = @(
                    [pscustomobject]@{
                        intent = 'available'
                        target = [pscustomobject]@{
                            '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                        }
                        settings = $null
                    }
                )
            }
        }

        $newAssignment = @{
            '@odata.type' = '#microsoft.graph.mobileAppAssignment'
            intent        = 'available'
            target        = @{
                '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
            }
            settings      = $null
        }

        $body = New-InTUIMobileAppAssignmentRequestBody -AppId 'app-1' -Assignment $newAssignment

        $body.mobileAppAssignments | Should -HaveCount 1
        $body.mobileAppAssignments[0].target.'@odata.type' | Should -Be '#microsoft.graph.allDevicesAssignmentTarget'
    }

    It 'Should return null when existing assignments cannot be loaded' {
        Mock Invoke-InTUIGraphRequest -MockWith { return $null }

        $newAssignment = @{
            '@odata.type' = '#microsoft.graph.mobileAppAssignment'
            intent        = 'available'
            target        = @{
                '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
            }
            settings      = $null
        }

        $body = New-InTUIMobileAppAssignmentRequestBody -AppId 'app-1' -Assignment $newAssignment

        $body | Should -BeNullOrEmpty
    }
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

Describe 'Group List Query Parameters' {
    It 'Should not request server-side sorting for security group filters' {
        $params = New-InTUIGroupListQueryParams -TypeFilter 'Security'

        $params.Filter | Should -Be 'securityEnabled eq true and mailEnabled eq false'
        $params.Headers['ConsistencyLevel'] | Should -Be 'eventual'
        $params.ContainsKey('OrderBy') | Should -BeFalse
    }

    It 'Should not request server-side sorting for Microsoft 365 group filters' {
        $params = New-InTUIGroupListQueryParams -TypeFilter 'Microsoft365'

        $params.Filter | Should -Be "groupTypes/any(g:g eq 'Unified')"
        $params.Headers['ConsistencyLevel'] | Should -Be 'eventual'
        $params.ContainsKey('OrderBy') | Should -BeFalse
    }

    It 'Should keep server-side sorting for unfiltered group lists' {
        $params = New-InTUIGroupListQueryParams

        $params.OrderBy | Should -Be 'displayName'
        $params.ContainsKey('Filter') | Should -BeFalse
    }

    It 'Should not request server-side sorting for group searches' {
        $params = New-InTUIGroupListQueryParams -SearchTerm 'micro'

        $params.Search | Should -Be '"displayName:micro" OR "mail:micro"'
        $params.PageSize | Should -Be 100
        $params.IncludeCount | Should -BeTrue
        $params.Headers['ConsistencyLevel'] | Should -Be 'eventual'
        $params.ContainsKey('Filter') | Should -BeFalse
        $params.ContainsKey('OrderBy') | Should -BeFalse
    }
}

Describe 'Compliance Policy List Query Parameters' {
    It 'Should not request unsupported server-side filtering for searches' {
        $params = New-InTUICompliancePolicyListQueryParams -SearchTerm 'OIB'

        $params.Uri | Should -Be '/deviceManagement/deviceCompliancePolicies'
        $params.Beta | Should -BeTrue
        $params.PageSize | Should -Be 200
        $params.ContainsKey('Filter') | Should -BeFalse
    }

    It 'Should use the standard page size when not searching' {
        $params = New-InTUICompliancePolicyListQueryParams

        $params.PageSize | Should -Be 25
        $params.ContainsKey('Filter') | Should -BeFalse
    }
}

Describe 'Get-InTUIFilteredCompliancePolicy' {
    BeforeAll {
        $script:CompliancePolicySamples = @(
            [pscustomobject]@{
                displayName   = 'Win - OIB - Compliance'
                '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'
            }
            [pscustomobject]@{
                displayName   = 'macOS - Platform Security'
                '@odata.type' = '#microsoft.graph.macOSCompliancePolicy'
            }
            [pscustomobject]@{
                displayName   = 'Android Work Profile'
                '@odata.type' = '#microsoft.graph.androidWorkProfileCompliancePolicy'
            }
        )
    }

    It 'Should filter searches by display name client-side' {
        $result = Get-InTUIFilteredCompliancePolicy -Policy $script:CompliancePolicySamples -SearchTerm 'oib'

        $result | Should -HaveCount 1
        $result[0].displayName | Should -Be 'Win - OIB - Compliance'
    }

    It 'Should combine platform and search filters client-side' {
        $result = Get-InTUIFilteredCompliancePolicy -Policy $script:CompliancePolicySamples -PlatformFilter 'macOS' -SearchTerm 'platform'

        $result | Should -HaveCount 1
        $result[0].displayName | Should -Be 'macOS - Platform Security'
    }

    It 'Should return no results when the search term does not match' {
        $result = Get-InTUIFilteredCompliancePolicy -Policy $script:CompliancePolicySamples -SearchTerm 'missing'

        $result | Should -HaveCount 0
    }
}

Describe 'Sign-in Log Query Parameters' {
    It 'Should request only a small recent sign-in log page' {
        $referenceTime = [datetime]'2026-05-06T12:00:00Z'

        $params = New-InTUISignInLogQueryParams -ReferenceTime $referenceTime

        $params.Uri | Should -Be '/auditLogs/signIns'
        $params.PageSize | Should -Be 10
        $params.Select | Should -Be 'id,userDisplayName,userPrincipalName,appDisplayName,ipAddress,status,createdDateTime,conditionalAccessStatus'
        $params.Filter | Should -Be 'createdDateTime ge 2026-05-05T12:00:00Z'
    }

    It 'Should combine the recent time window with failure filters' {
        $referenceTime = [datetime]'2026-05-06T12:00:00Z'

        $params = New-InTUISignInLogQueryParams -Filter 'status/errorCode ne 0' -ReferenceTime $referenceTime

        $params.Filter | Should -Be 'createdDateTime ge 2026-05-05T12:00:00Z and (status/errorCode ne 0)'
    }
}

Describe 'Autopilot Device List Query Parameters' {
    It 'Should request a small Autopilot device page with only list fields' {
        $params = New-InTUIAutopilotDeviceListQueryParams

        $params.Uri | Should -Be '/deviceManagement/windowsAutopilotDeviceIdentities'
        $params.Beta | Should -BeTrue
        $params.PageSize | Should -Be 10
        $params.Select | Should -Be 'id,serialNumber,model,groupTag,enrollmentState,lastContactedDateTime'
    }

    It 'Should detect Graph errors from the Autopilot device list endpoint' {
        $errorInfo = [pscustomobject]@{
            StatusCode = 'InternalServerError'
            Uri        = 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?$top=10'
        }

        Test-InTUIAutopilotDeviceListError -ErrorInfo $errorInfo | Should -BeTrue
    }
}

Describe 'BitLocker Recovery Key Permissions' {
    It 'Should detect Forbidden errors from the BitLocker recovery keys endpoint' {
        $errorInfo = [pscustomobject]@{
            StatusCode = 'Forbidden'
            Uri        = 'https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys?$filter=deviceId eq ''device-1'''
        }

        Test-InTUIBitLockerPermissionError -ErrorInfo $errorInfo | Should -BeTrue
    }

    It 'Should not treat unrelated Forbidden errors as BitLocker permission errors' {
        $errorInfo = [pscustomobject]@{
            StatusCode = 'Forbidden'
            Uri        = 'https://graph.microsoft.com/v1.0/users'
        }

        Test-InTUIBitLockerPermissionError -ErrorInfo $errorInfo | Should -BeFalse
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

    It 'Should collect all pages when -All is specified' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'
        $script:PageCallCount = 0

        Mock Invoke-MgGraphRequest -MockWith {
            $script:PageCallCount++
            if ($script:PageCallCount -eq 1) {
                return @{
                    value            = @(@{ id = '1' })
                    '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=next'
                }
            }

            return @{ value = @(@{ id = '2' }) }
        }

        $result = Invoke-InTUIGraphRequest -Uri '/users' -All

        $result | Should -HaveCount 2
        $result[0].id | Should -Be '1'
        $result[1].id | Should -Be '2'
    }

    It 'Should stop pagination after MaxPages' {
        $script:GraphBaseUrl = 'https://graph.microsoft.com/v1.0'

        Mock Invoke-MgGraphRequest -MockWith {
            return @{
                value            = @(@{ id = '1' })
                '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/users?$skiptoken=loop'
            }
        }

        $result = Invoke-InTUIGraphRequest -Uri '/users' -All -MaxPages 2

        $result | Should -BeNullOrEmpty
        $script:LastGraphError.Message | Should -Match 'pagination exceeded max page limit'
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

    It 'Should request BitLocker recovery key scopes by default' {
        Mock Connect-MgGraph {
            param($Scopes, $NoWelcome, $Environment, $TenantId)
            $script:CapturedScopes = $Scopes
        }
        Mock Get-MgContext { return @{ TenantId = 'test'; Account = 'test@test.com' } }

        Connect-InTUIGraph -Environment 'Global'

        $script:CapturedScopes | Should -Contain 'BitlockerKey.ReadBasic.All'
        $script:CapturedScopes | Should -Contain 'BitlockerKey.Read.All'
    }

    It 'Should request Autopilot service configuration scope by default' {
        Mock Connect-MgGraph {
            param($Scopes, $NoWelcome, $Environment, $TenantId)
            $script:CapturedScopes = $Scopes
        }
        Mock Get-MgContext { return @{ TenantId = 'test'; Account = 'test@test.com' } }

        Connect-InTUIGraph -Environment 'Global'

        $script:CapturedScopes | Should -Contain 'DeviceManagementServiceConfig.Read.All'
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

    It 'Should include TotalCount key in result' {
        Mock Invoke-MgGraphRequest -MockWith {
            return @{
                value = @(@{ id = '1' })
                '@odata.count' = 42
            }
        }

        $result = Get-InTUIPagedResults -Uri '/users'
        $result.ContainsKey('TotalCount') | Should -BeTrue
        $result.TotalCount | Should -Be 42
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

    It 'Should build URI with quoted search expressions without double wrapping' {
        Mock Invoke-MgGraphRequest -MockWith {
            param($Uri)
            $script:CapturedUri = $Uri
            return @{ value = @() }
        }

        Get-InTUIPagedResults -Uri '/groups' -Search '"displayName:micro" OR "mail:micro"' -IncludeCount
        $script:CapturedUri | Should -BeLike '*$search="displayName:micro" OR "mail:micro"*'
        $script:CapturedUri | Should -BeLike '*$count=true*'
        $script:CapturedUri | Should -Not -BeLike '*$search=""displayName*'
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

Describe 'PIM Role Activation Helpers' {
    BeforeEach {
        $script:Connected = $true
        $script:LastGraphError = $null
        $script:LogFilePath = $null
    }

    It 'Should return PIM connection scopes without duplicates' {
        $scopes = Get-InTUIPimConnectionScopes

        $scopes | Should -Contain 'RoleEligibilitySchedule.Read.Directory'
        $scopes | Should -Contain 'RoleAssignmentSchedule.ReadWrite.Directory'
        $scopes | Should -Contain 'RoleManagement.Read.Directory'
        $scopes.Count | Should -Be (($scopes | Select-Object -Unique).Count)
    }

    It 'Should convert integer hours to Graph duration format' {
        ConvertTo-InTUIPimDuration -Hours 2 | Should -Be 'PT2H'
    }

    It 'Should require a non-empty reason' {
        Test-InTUIPimReason -Reason '  ' | Should -BeFalse
        Test-InTUIPimReason -Reason 'INC12345' | Should -BeTrue
    }

    It 'Should redact long reason text for local logs' {
        $reason = 'INC12345 investigating privileged access for endpoint incident'

        $redacted = ConvertTo-InTUIPimRedactedReason -Reason $reason -PrefixLength 10

        $redacted | Should -Be 'INC12345 i... [redacted]'
    }

    It 'Should build a stable role key from role definition and scope' {
        $role = [pscustomobject]@{
            RoleDefinitionId = 'role-1'
            DirectoryScopeId = '/administrativeUnits/au-1'
            AppScopeId       = $null
        }

        Get-InTUIPimRoleKey -Role $role | Should -Be 'role-1|/administrativeUnits/au-1|'
    }

    It 'Should display tenant scope for empty or root directory scopes' {
        Get-InTUIPimScopeLabel -DirectoryScopeId '/' | Should -Be 'Tenant'
        Get-InTUIPimScopeLabel -DirectoryScopeId '' | Should -Be 'Tenant'
    }

    It 'Should parse eligible role schedule instances into role items' {
        $schedule = [pscustomobject]@{
            id               = 'eligibility-1'
            principalId      = 'user-1'
            roleDefinitionId = 'role-1'
            directoryScopeId = '/'
            appScopeId       = $null
            roleDefinition   = [pscustomobject]@{ displayName = 'Global Reader' }
        }

        $role = ConvertTo-InTUIPimRoleItem -Schedule $schedule

        $role.DisplayName | Should -Be 'Global Reader'
        $role.PrincipalId | Should -Be 'user-1'
        $role.RoleDefinitionId | Should -Be 'role-1'
        $role.DirectoryScopeId | Should -Be '/'
    }

    It 'Should parse PascalCase PIM schedule objects into role items' {
        $schedule = [pscustomobject]@{
            Id               = 'eligibility-1'
            PrincipalId      = 'user-1'
            RoleDefinitionId = 'role-1'
            DirectoryScopeId = '/'
            AppScopeId       = $null
            RoleDefinition   = [pscustomobject]@{ DisplayName = 'Global Reader' }
        }

        $role = ConvertTo-InTUIPimRoleItem -Schedule $schedule

        $role.DisplayName | Should -Be 'Global Reader'
        $role.PrincipalId | Should -Be 'user-1'
        $role.RoleDefinitionId | Should -Be 'role-1'
        $role.DirectoryScopeId | Should -Be '/'
    }

    It 'Should parse dictionary-shaped PIM schedule rows into role items' {
        $schedule = @{
            id               = 'eligibility-1'
            principalId      = 'user-1'
            roleDefinitionId = 'role-1'
            directoryScopeId = '/'
            appScopeId       = $null
            roleDefinition   = @{ displayName = 'Global Reader' }
        }

        $role = ConvertTo-InTUIPimRoleItem -Schedule $schedule

        $role.DisplayName | Should -Be 'Global Reader'
        $role.PrincipalId | Should -Be 'user-1'
        $role.RoleDefinitionId | Should -Be 'role-1'
        $role.DirectoryScopeId | Should -Be '/'
    }

    It 'Should resolve dictionary-shaped role definition names' {
        $roles = @(
            [pscustomobject]@{
                DisplayName      = 'role-1'
                RoleDefinitionId = 'role-1'
            }
        )
        Mock Invoke-InTUIGraphRequest {
            return @(
                @{
                    id          = 'role-1'
                    displayName = 'Global Reader'
                }
            )
        } -ParameterFilter { $Uri -like '*roleDefinitions*' }

        $result = Set-InTUIPimRoleDisplayName -Roles $roles

        $result[0].DisplayName | Should -Be 'Global Reader'
    }

    It 'Should parse PIM schedule values from AdditionalProperties' {
        $schedule = [pscustomobject]@{
            AdditionalProperties = @{
                id               = 'eligibility-1'
                principalId      = 'user-1'
                roleDefinitionId = 'role-1'
                directoryScopeId = '/'
                roleDefinition   = @{ displayName = 'Global Reader' }
            }
        }

        $role = ConvertTo-InTUIPimRoleItem -Schedule $schedule

        $role.DisplayName | Should -Be 'Global Reader'
        $role.PrincipalId | Should -Be 'user-1'
        $role.RoleDefinitionId | Should -Be 'role-1'
        $role.DirectoryScopeId | Should -Be '/'
    }

    It 'Should normalize raw PIM item collections through JSON when direct conversion fails' {
        $items = @(
            [pscustomobject]@{
                AdditionalProperties = @{
                    id               = 'eligibility-1'
                    principalId      = 'user-1'
                    roleDefinitionId = 'role-1'
                    directoryScopeId = '/'
                    roleDefinition   = @{ displayName = 'Global Reader' }
                }
            }
        )

        $roles = ConvertTo-InTUIPimRoleCollection -Items $items -Source 'Test'

        $roles | Should -HaveCount 1
        $roles[0].DisplayName | Should -Be 'Global Reader'
    }

    It 'Should ignore null PIM schedule items returned by Graph' {
        Mock Invoke-InTUIGraphRequest {
            return @(
                $null,
                [pscustomobject]@{
                    id               = 'eligibility-1'
                    principalId      = 'user-1'
                    roleDefinitionId = 'role-1'
                    directoryScopeId = '/'
                    roleDefinition   = [pscustomobject]@{ displayName = 'Global Reader' }
                }
            )
        }

        $roles = Get-InTUIPimEligibleDirectoryRole

        $roles | Should -HaveCount 1
        $roles[0].DisplayName | Should -Be 'Global Reader'
    }

    It 'Should ignore PIM schedule items missing activation identifiers' {
        Mock Invoke-InTUIGraphRequest {
            return @(
                [pscustomobject]@{
                    id               = 'missing-principal'
                    roleDefinitionId = 'role-1'
                    directoryScopeId = '/'
                },
                [pscustomobject]@{
                    id          = 'missing-role'
                    principalId = 'user-1'
                }
            )
        }

        Get-InTUIPimEligibleDirectoryRole | Should -BeNullOrEmpty
    }

    It 'Should bypass cache when loading PIM eligible roles' {
        Mock Invoke-InTUIGraphRequest {
            return @(
                [pscustomobject]@{
                    id               = 'eligibility-1'
                    principalId      = 'user-1'
                    roleDefinitionId = 'role-1'
                    directoryScopeId = '/'
                    roleDefinition   = [pscustomobject]@{ displayName = 'Global Reader' }
                }
            )
        } -ParameterFilter {
            $Uri -like '*roleEligibilityScheduleInstances*' -and $Beta -and $All -and $NoCache
        }

        $roles = Get-InTUIPimEligibleDirectoryRole

        $roles | Should -HaveCount 1

        Should -Invoke Invoke-InTUIGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*roleEligibilityScheduleInstances*' -and $Beta -and $All -and $NoCache
        }
    }

    It 'Should treat paged PIM dictionary rows as rows, not Graph envelopes' {
        Mock Invoke-InTUIGraphRequest {
            return @(
                @{
                    id               = 'eligibility-1'
                    principalId      = 'user-1'
                    roleDefinitionId = 'role-1'
                    directoryScopeId = '/'
                    roleDefinition   = @{ displayName = 'Global Reader' }
                },
                @{
                    id               = 'eligibility-2'
                    principalId      = 'user-1'
                    roleDefinitionId = 'role-2'
                    directoryScopeId = '/'
                    roleDefinition   = @{ displayName = 'Intune Administrator' }
                }
            )
        } -ParameterFilter {
            $Uri -like '*roleEligibilityScheduleInstances*' -and $All
        }

        $roles = Get-InTUIPimEligibleDirectoryRole

        $roles | Should -HaveCount 2
        $roles.DisplayName | Should -Contain 'Global Reader'
        $roles.DisplayName | Should -Contain 'Intune Administrator'
    }

    It 'Should fall back to role eligibility schedules when schedule instances do not convert' {
        Mock Invoke-InTUIGraphRequest {
            return @(
                [pscustomobject]@{
                    id               = 'missing-principal'
                    roleDefinitionId = 'role-1'
                    directoryScopeId = '/'
                }
            )
        } -ParameterFilter { $Uri -like '*roleEligibilityScheduleInstances*' }
        Mock Invoke-InTUIGraphRequest {
            return @(
                [pscustomobject]@{
                    id               = 'schedule-1'
                    principalId      = 'user-1'
                    roleDefinitionId = 'role-1'
                    directoryScopeId = '/'
                    memberType       = 'Direct'
                    status           = 'Provisioned'
                }
            )
        } -ParameterFilter { $Uri -like '*roleEligibilitySchedules*' }
        Mock Invoke-InTUIGraphRequest {
            return @(
                [pscustomobject]@{
                    id          = 'role-1'
                    displayName = 'Global Reader'
                }
            )
        } -ParameterFilter { $Uri -like '*roleDefinitions*' }

        $roles = Get-InTUIPimEligibleDirectoryRole

        $roles | Should -HaveCount 1
        $roles[0].DisplayName | Should -Be 'Global Reader'
        $roles[0].PrincipalId | Should -Be 'user-1'
    }

    It 'Should bypass cache when loading PIM active roles' {
        Mock Invoke-InTUIGraphRequest { return @() } -ParameterFilter {
            $Uri -like '*roleAssignmentScheduleInstances*' -and $Beta -and $All -and $NoCache
        }

        Get-InTUIPimActiveDirectoryRole | Should -BeNullOrEmpty

        Should -Invoke Invoke-InTUIGraphRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*roleAssignmentScheduleInstances*' -and $Beta -and $All -and $NoCache
        }
    }

    It 'Should exclude already-active roles by role definition and scope' {
        $eligible = @(
            [pscustomobject]@{ DisplayName = 'Global Reader'; RoleDefinitionId = 'role-1'; DirectoryScopeId = '/'; AppScopeId = $null },
            [pscustomobject]@{ DisplayName = 'Security Reader'; RoleDefinitionId = 'role-2'; DirectoryScopeId = '/administrativeUnits/au-1'; AppScopeId = $null }
        )
        $active = @(
            [pscustomobject]@{ DisplayName = 'Global Reader'; RoleDefinitionId = 'role-1'; DirectoryScopeId = '/'; AppScopeId = $null }
        )

        $result = Select-InTUIPimActivatableRole -EligibleRoles $eligible -ActiveRoles $active

        $result | Should -HaveCount 1
        $result[0].DisplayName | Should -Be 'Security Reader'
    }

    It 'Should keep eligible roles visible when active assignments are also present' {
        $eligible = @(
            [pscustomobject]@{ DisplayName = 'Global Administrator'; RoleDefinitionId = 'role-1'; DirectoryScopeId = '/'; AppScopeId = $null },
            [pscustomobject]@{ DisplayName = 'Intune Administrator'; RoleDefinitionId = 'role-2'; DirectoryScopeId = '/'; AppScopeId = $null },
            [pscustomobject]@{ DisplayName = 'User Administrator'; RoleDefinitionId = 'role-3'; DirectoryScopeId = '/'; AppScopeId = $null },
            [pscustomobject]@{ DisplayName = 'Global Reader'; RoleDefinitionId = 'role-4'; DirectoryScopeId = '/'; AppScopeId = $null }
        )
        $active = @(
            [pscustomobject]@{ DisplayName = 'Global Administrator'; RoleDefinitionId = 'role-1'; DirectoryScopeId = '/'; AppScopeId = $null }
        )

        $availableRoles = @($eligible)

        $active | Should -HaveCount 1
        $availableRoles | Should -HaveCount 4
        $availableRoles.DisplayName | Should -Contain 'Intune Administrator'
        $availableRoles.DisplayName | Should -Contain 'User Administrator'
        $availableRoles.DisplayName | Should -Contain 'Global Reader'
    }

    It 'Should build selfActivate request body preserving directory scope' {
        $role = [pscustomobject]@{
            PrincipalId      = 'user-1'
            RoleDefinitionId = 'role-1'
            DirectoryScopeId = '/administrativeUnits/au-1'
            AppScopeId       = $null
        }
        $start = [datetime]'2026-05-17T20:00:00Z'

        $body = New-InTUIPimActivationRequestBody -Role $role -Hours 3 -Reason 'INC12345' -StartDateTime $start

        $body.action | Should -Be 'selfActivate'
        $body.principalId | Should -Be 'user-1'
        $body.roleDefinitionId | Should -Be 'role-1'
        $body.directoryScopeId | Should -Be '/administrativeUnits/au-1'
        $body.justification | Should -Be 'INC12345'
        $body.scheduleInfo.expiration.type | Should -Be 'afterDuration'
        $body.scheduleInfo.expiration.duration | Should -Be 'PT3H'
    }

    It 'Should throw when building an activation body with an empty reason' {
        $role = [pscustomobject]@{
            PrincipalId      = 'user-1'
            RoleDefinitionId = 'role-1'
            DirectoryScopeId = '/'
        }

        { New-InTUIPimActivationRequestBody -Role $role -Hours 1 -Reason ' ' } | Should -Throw
    }

    It 'Should throw when building an activation body without a principal id' {
        $role = [pscustomobject]@{
            RoleDefinitionId = 'role-1'
            DirectoryScopeId = '/'
        }

        { New-InTUIPimActivationRequestBody -Role $role -Hours 1 -Reason 'INC12345' } | Should -Throw
    }

    It 'Should throw when building an activation body without a role definition id' {
        $role = [pscustomobject]@{
            PrincipalId      = 'user-1'
            DirectoryScopeId = '/'
        }

        { New-InTUIPimActivationRequestBody -Role $role -Hours 1 -Reason 'INC12345' } | Should -Throw
    }

    It 'Should continue activating remaining roles after one failure' {
        $roles = @(
            [pscustomobject]@{ DisplayName = 'Global Reader'; PrincipalId = 'user-1'; RoleDefinitionId = 'role-1'; DirectoryScopeId = '/'; AppScopeId = $null },
            [pscustomobject]@{ DisplayName = 'Security Reader'; PrincipalId = 'user-1'; RoleDefinitionId = 'role-2'; DirectoryScopeId = '/'; AppScopeId = $null }
        )
        $callCount = 0
        Mock Invoke-InTUIGraphRequest {
            $script:LastGraphError = [pscustomobject]@{ Message = 'Denied by policy' }
            return $null
        } -ParameterFilter { $Body.roleDefinitionId -eq 'role-1' }
        Mock Invoke-InTUIGraphRequest {
            $callCount++
            return [pscustomobject]@{ id = 'request-2'; status = 'Granted' }
        } -ParameterFilter { $Body.roleDefinitionId -eq 'role-2' }

        $results = Invoke-InTUIPimRoleActivation -Roles $roles -Hours 1 -Reason 'INC12345 investigating a device'

        $results | Should -HaveCount 2
        $results[0].Status | Should -Be 'Failed'
        $results[0].Error | Should -Be 'Denied by policy'
        $results[1].Status | Should -Be 'Granted'
        $results[1].RequestId | Should -Be 'request-2'
    }

    It 'Should not log full reason text when activating roles' {
        $testLogDir = Join-Path $TestDrive "logs_$(Get-Random)"
        New-Item -Path $testLogDir -ItemType Directory -Force | Out-Null
        Initialize-InTUILog -LogDirectory $testLogDir
        $role = [pscustomobject]@{
            DisplayName      = 'Global Reader'
            PrincipalId      = 'user-1'
            RoleDefinitionId = 'role-1'
            DirectoryScopeId = '/'
            AppScopeId       = $null
        }
        Mock Invoke-InTUIGraphRequest {
            return [pscustomobject]@{ id = 'request-1'; status = 'Granted' }
        }

        Invoke-InTUIPimRoleActivation -Roles @($role) -Hours 1 -Reason 'INC12345 investigating highly sensitive customer issue'

        $content = Get-Content $script:LogFilePath -Raw
        $content | Should -Not -Match 'highly sensitive customer issue'
        $content | Should -Match 'redacted'
    }
}
