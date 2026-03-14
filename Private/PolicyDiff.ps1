function Show-InTUIPolicyDiffView {
    <#
    .SYNOPSIS
        Compare two configuration profiles or compliance policies side by side.
    #>
    [CmdletBinding()]
    param()

    $exitView = $false

    while (-not $exitView) {
        Clear-Host
        Show-InTUIHeader
        Show-InTUIBreadcrumb -Path @('Home', 'Policy Diff')

        $choices = @('Settings Catalog Profiles', 'Legacy Configuration Profiles', 'Compliance Policies', '─────────────', 'Back to Home')
        $selection = Show-InTUIMenu -Title "[mauve]Policy Diff[/]" -Choices $choices

        switch ($selection) {
            'Settings Catalog Profiles' {
                Invoke-InTUICatalogProfileDiff
            }
            'Legacy Configuration Profiles' {
                Invoke-InTUILegacyProfileDiff
            }
            'Compliance Policies' {
                Invoke-InTUICompliancePolicyDiff
            }
            'Back to Home' {
                $exitView = $true
            }
            default { continue }
        }
    }
}

function Invoke-InTUICatalogProfileDiff {
    <#
    .SYNOPSIS
        Compares two Settings Catalog profiles.
    #>
    [CmdletBinding()]
    param()

    $profiles = Show-InTUILoading -Title "[mauve]Loading Settings Catalog profiles...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/deviceManagement/configurationPolicies' -Beta -PageSize 100 `
            -Select 'id,name,platforms,lastModifiedDateTime'
    }

    if ($null -eq $profiles -or $profiles.Results.Count -lt 2) {
        Show-InTUIWarning "Need at least 2 Settings Catalog profiles to compare."
        Read-InTUIKey
        return
    }

    $profileNames = @()
    foreach ($p in $profiles.Results) {
        $profileNames += "[white]$(ConvertTo-InTUISafeMarkup -Text $p.name)[/] [grey]| $($p.platforms ?? 'N/A')[/]"
    }

    # Select Policy A
    Write-InTUIText "[mauve]Select Policy A:[/]"
    $choiceMapA = Get-InTUIChoiceMap -Choices $profileNames
    $menuChoicesA = @($choiceMapA.Choices + 'Cancel')
    $selA = Show-InTUIMenu -Title "[mauve]Policy A[/]" -Choices $menuChoicesA
    if ($selA -eq 'Cancel') { return }
    $idxA = $choiceMapA.IndexMap[$selA]
    if ($null -eq $idxA) { return }
    $policyA = $profiles.Results[$idxA]

    # Select Policy B
    Write-InTUIText "[mauve]Select Policy B:[/]"
    $choiceMapB = Get-InTUIChoiceMap -Choices $profileNames
    $menuChoicesB = @($choiceMapB.Choices + 'Cancel')
    $selB = Show-InTUIMenu -Title "[mauve]Policy B[/]" -Choices $menuChoicesB
    if ($selB -eq 'Cancel') { return }
    $idxB = $choiceMapB.IndexMap[$selB]
    if ($null -eq $idxB) { return }
    $policyB = $profiles.Results[$idxB]

    if ($policyA.id -eq $policyB.id) {
        Show-InTUIWarning "Same policy selected for both. Choose two different policies."
        Read-InTUIKey
        return
    }

    # Fetch settings for both
    $settingsData = Show-InTUILoading -Title "[mauve]Loading settings...[/]" -ScriptBlock {
        $sA = Invoke-InTUIGraphRequest -Uri "/deviceManagement/configurationPolicies/$($policyA.id)/settings?`$expand=settingDefinitions&`$top=100" -Beta
        $sB = Invoke-InTUIGraphRequest -Uri "/deviceManagement/configurationPolicies/$($policyB.id)/settings?`$expand=settingDefinitions&`$top=100" -Beta
        @{
            SettingsA = $sA
            SettingsB = $sB
        }
    }

    $itemsA = if ($settingsData.SettingsA.value) { @($settingsData.SettingsA.value) } else { @() }
    $itemsB = if ($settingsData.SettingsB.value) { @($settingsData.SettingsB.value) } else { @() }

    # Build lookup by settingDefinitionId
    $mapA = @{}
    foreach ($s in $itemsA) {
        $defId = $s.settingInstance.settingDefinitionId ?? $s.id
        $val = $s.settingInstance.simpleSettingValue.value ?? $s.settingInstance.choiceSettingValue.value ?? ($s.settingInstance | ConvertTo-Json -Depth 3 -Compress)
        $mapA[$defId] = $val
    }

    $mapB = @{}
    foreach ($s in $itemsB) {
        $defId = $s.settingInstance.settingDefinitionId ?? $s.id
        $val = $s.settingInstance.simpleSettingValue.value ?? $s.settingInstance.choiceSettingValue.value ?? ($s.settingInstance | ConvertTo-Json -Depth 3 -Compress)
        $mapB[$defId] = $val
    }

    $allKeys = @($mapA.Keys) + @($mapB.Keys) | Sort-Object -Unique
    $diffRows = Compare-InTUIPolicySettings -MapA $mapA -MapB $mapB -AllKeys $allKeys

    Show-InTUIPolicyDiffTable -PolicyAName $policyA.name -PolicyBName $policyB.name -DiffRows $diffRows
}

function Invoke-InTUILegacyProfileDiff {
    <#
    .SYNOPSIS
        Compares two legacy device configuration profiles.
    #>
    [CmdletBinding()]
    param()

    $profiles = Show-InTUILoading -Title "[mauve]Loading legacy profiles...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/deviceManagement/deviceConfigurations' -Beta -PageSize 100 `
            -Select 'id,displayName,lastModifiedDateTime'
    }

    if ($null -eq $profiles -or $profiles.Results.Count -lt 2) {
        Show-InTUIWarning "Need at least 2 legacy profiles to compare."
        Read-InTUIKey
        return
    }

    $profileNames = @()
    foreach ($p in $profiles.Results) {
        $profileNames += "[white]$(ConvertTo-InTUISafeMarkup -Text $p.displayName)[/]"
    }

    Write-InTUIText "[mauve]Select Policy A:[/]"
    $choiceMapA = Get-InTUIChoiceMap -Choices $profileNames
    $selA = Show-InTUIMenu -Title "[mauve]Policy A[/]" -Choices @($choiceMapA.Choices + 'Cancel')
    if ($selA -eq 'Cancel') { return }
    $idxA = $choiceMapA.IndexMap[$selA]
    if ($null -eq $idxA) { return }

    Write-InTUIText "[mauve]Select Policy B:[/]"
    $choiceMapB = Get-InTUIChoiceMap -Choices $profileNames
    $selB = Show-InTUIMenu -Title "[mauve]Policy B[/]" -Choices @($choiceMapB.Choices + 'Cancel')
    if ($selB -eq 'Cancel') { return }
    $idxB = $choiceMapB.IndexMap[$selB]
    if ($null -eq $idxB) { return }

    $policyA = $profiles.Results[$idxA]
    $policyB = $profiles.Results[$idxB]

    if ($policyA.id -eq $policyB.id) {
        Show-InTUIWarning "Same policy selected for both."
        Read-InTUIKey
        return
    }

    $fullData = Show-InTUILoading -Title "[mauve]Loading full policy details...[/]" -ScriptBlock {
        $fA = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$($policyA.id)" -Beta
        $fB = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceConfigurations/$($policyB.id)" -Beta
        @{ FullA = $fA; FullB = $fB }
    }

    # Compare non-metadata properties
    $skipProps = @('id', '@odata.type', '@odata.context', 'createdDateTime', 'lastModifiedDateTime',
                   'version', 'displayName', 'description', 'assignments', 'roleScopeTagIds')

    $mapA = @{}
    $mapB = @{}
    $propsA = $fullData.FullA | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    $propsB = $fullData.FullB | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    foreach ($prop in $propsA) {
        if ($skipProps -contains $prop) { continue }
        $mapA[$prop] = "$($fullData.FullA.$prop)"
    }
    foreach ($prop in $propsB) {
        if ($skipProps -contains $prop) { continue }
        $mapB[$prop] = "$($fullData.FullB.$prop)"
    }

    $allKeys = @($mapA.Keys) + @($mapB.Keys) | Sort-Object -Unique
    $diffRows = Compare-InTUIPolicySettings -MapA $mapA -MapB $mapB -AllKeys $allKeys

    Show-InTUIPolicyDiffTable -PolicyAName $policyA.displayName -PolicyBName $policyB.displayName -DiffRows $diffRows
}

function Invoke-InTUICompliancePolicyDiff {
    <#
    .SYNOPSIS
        Compares two compliance policies.
    #>
    [CmdletBinding()]
    param()

    $policies = Show-InTUILoading -Title "[mauve]Loading compliance policies...[/]" -ScriptBlock {
        Get-InTUIPagedResults -Uri '/deviceManagement/deviceCompliancePolicies' -Beta -PageSize 100 `
            -Select 'id,displayName,lastModifiedDateTime'
    }

    if ($null -eq $policies -or $policies.Results.Count -lt 2) {
        Show-InTUIWarning "Need at least 2 compliance policies to compare."
        Read-InTUIKey
        return
    }

    $policyNames = @()
    foreach ($p in $policies.Results) {
        $policyNames += "[white]$(ConvertTo-InTUISafeMarkup -Text $p.displayName)[/]"
    }

    Write-InTUIText "[mauve]Select Policy A:[/]"
    $choiceMapA = Get-InTUIChoiceMap -Choices $policyNames
    $selA = Show-InTUIMenu -Title "[mauve]Policy A[/]" -Choices @($choiceMapA.Choices + 'Cancel')
    if ($selA -eq 'Cancel') { return }
    $idxA = $choiceMapA.IndexMap[$selA]
    if ($null -eq $idxA) { return }

    Write-InTUIText "[mauve]Select Policy B:[/]"
    $choiceMapB = Get-InTUIChoiceMap -Choices $policyNames
    $selB = Show-InTUIMenu -Title "[mauve]Policy B[/]" -Choices @($choiceMapB.Choices + 'Cancel')
    if ($selB -eq 'Cancel') { return }
    $idxB = $choiceMapB.IndexMap[$selB]
    if ($null -eq $idxB) { return }

    $policyA = $policies.Results[$idxA]
    $policyB = $policies.Results[$idxB]

    if ($policyA.id -eq $policyB.id) {
        Show-InTUIWarning "Same policy selected for both."
        Read-InTUIKey
        return
    }

    $fullData = Show-InTUILoading -Title "[mauve]Loading full policy details...[/]" -ScriptBlock {
        $fA = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceCompliancePolicies/$($policyA.id)" -Beta
        $fB = Invoke-InTUIGraphRequest -Uri "/deviceManagement/deviceCompliancePolicies/$($policyB.id)" -Beta
        @{ FullA = $fA; FullB = $fB }
    }

    $skipProps = @('id', '@odata.type', '@odata.context', 'createdDateTime', 'lastModifiedDateTime',
                   'version', 'displayName', 'description', 'assignments', 'roleScopeTagIds',
                   'scheduledActionsForRule')

    $mapA = @{}
    $mapB = @{}
    $propsA = $fullData.FullA | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    $propsB = $fullData.FullB | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    foreach ($prop in $propsA) {
        if ($skipProps -contains $prop) { continue }
        $mapA[$prop] = "$($fullData.FullA.$prop)"
    }
    foreach ($prop in $propsB) {
        if ($skipProps -contains $prop) { continue }
        $mapB[$prop] = "$($fullData.FullB.$prop)"
    }

    $allKeys = @($mapA.Keys) + @($mapB.Keys) | Sort-Object -Unique
    $diffRows = Compare-InTUIPolicySettings -MapA $mapA -MapB $mapB -AllKeys $allKeys

    Show-InTUIPolicyDiffTable -PolicyAName $policyA.displayName -PolicyBName $policyB.displayName -DiffRows $diffRows
}

function Compare-InTUIPolicySettings {
    <#
    .SYNOPSIS
        Compares two setting maps and returns diff entries.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$MapA,

        [Parameter(Mandatory)]
        [hashtable]$MapB,

        [Parameter(Mandatory)]
        [array]$AllKeys
    )

    $results = @()
    foreach ($key in $AllKeys) {
        $valA = if ($MapA.ContainsKey($key)) { $MapA[$key] } else { $null }
        $valB = if ($MapB.ContainsKey($key)) { $MapB[$key] } else { $null }

        $isDifferent = $valA -ne $valB
        $onlyInA = ($null -ne $valA -and $null -eq $valB)
        $onlyInB = ($null -eq $valA -and $null -ne $valB)

        $results += [PSCustomObject]@{
            Name        = $key
            ValueA      = $valA ?? '(not set)'
            ValueB      = $valB ?? '(not set)'
            IsDifferent = $isDifferent
            OnlyInA     = $onlyInA
            OnlyInB     = $onlyInB
        }
    }

    return $results
}

function Show-InTUIPolicyDiffTable {
    <#
    .SYNOPSIS
        Renders the diff results as a color-coded table.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PolicyAName,

        [Parameter(Mandatory)]
        [string]$PolicyBName,

        [Parameter(Mandatory)]
        [array]$DiffRows
    )

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Policy Diff', 'Results')

    if ($DiffRows.Count -eq 0) {
        Show-InTUISuccess "No settings to compare."
        Read-InTUIKey
        return
    }

    $matchCount = @($DiffRows | Where-Object { -not $_.IsDifferent }).Count
    $diffCount = @($DiffRows | Where-Object { $_.IsDifferent }).Count

    $summaryContent = @"
[grey]Policy A:[/] [white]$(ConvertTo-InTUISafeMarkup -Text $PolicyAName)[/]
[grey]Policy B:[/] [white]$(ConvertTo-InTUISafeMarkup -Text $PolicyBName)[/]
[grey]Total Settings:[/] [white]$($DiffRows.Count)[/]  [green]Matching: $matchCount[/]  [red]Different: $diffCount[/]
"@

    Show-InTUIPanel -Title "[mauve]Diff Summary[/]" -Content $summaryContent -BorderColor Mauve

    $rows = @()
    foreach ($entry in $DiffRows) {
        $nameDisplay = $entry.Name

        # Truncate long values
        $valADisplay = if ($entry.ValueA.Length -gt 40) { $entry.ValueA.Substring(0, 37) + '...' } else { $entry.ValueA }
        $valBDisplay = if ($entry.ValueB.Length -gt 40) { $entry.ValueB.Substring(0, 37) + '...' } else { $entry.ValueB }

        $valADisplay = ConvertTo-InTUISafeMarkup -Text $valADisplay
        $valBDisplay = ConvertTo-InTUISafeMarkup -Text $valBDisplay

        if ($entry.OnlyInA) {
            $rows += , @("[yellow]$nameDisplay[/]", "[yellow]$valADisplay[/]", "[grey](not set)[/]")
        }
        elseif ($entry.OnlyInB) {
            $rows += , @("[yellow]$nameDisplay[/]", "[grey](not set)[/]", "[yellow]$valBDisplay[/]")
        }
        elseif ($entry.IsDifferent) {
            $rows += , @("[red]$nameDisplay[/]", "[red]$valADisplay[/]", "[red]$valBDisplay[/]")
        }
        else {
            $rows += , @("[green]$nameDisplay[/]", "[green]$valADisplay[/]", "[green]$valBDisplay[/]")
        }
    }

    Render-InTUITable -Title "Policy Comparison" -Columns @('Setting', "Policy A", "Policy B") -Rows $rows -BorderColor Mauve

    Read-InTUIKey
}
