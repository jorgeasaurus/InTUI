# InTUI Script Recording
# Records Graph API actions for playback/automation

function Start-InTUIRecording {
    <#
    .SYNOPSIS
        Starts recording Graph API actions.
    #>
    [CmdletBinding()]
    param()

    if ($script:RecordingEnabled) {
        Write-InTUILog -Level 'WARN' -Message "Recording already in progress"
        return $false
    }

    $script:RecordingEnabled = $true
    $script:RecordedActions = [System.Collections.Generic.List[hashtable]]::new()
    $script:RecordingStartTime = [DateTime]::UtcNow

    Write-InTUILog -Message "Recording started"
    return $true
}

function Stop-InTUIRecording {
    <#
    .SYNOPSIS
        Stops recording Graph API actions.
    .OUTPUTS
        Returns the recorded actions.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:RecordingEnabled) {
        Write-InTUILog -Level 'WARN' -Message "No recording in progress"
        return $null
    }

    $script:RecordingEnabled = $false
    $script:RecordingEndTime = [DateTime]::UtcNow

    $actions = $script:RecordedActions
    $duration = ($script:RecordingEndTime - $script:RecordingStartTime).TotalSeconds

    Write-InTUILog -Message "Recording stopped" -Context @{
        ActionCount = $actions.Count
        Duration = [math]::Round($duration)
    }

    return @{
        Actions   = $actions
        StartTime = $script:RecordingStartTime
        EndTime   = $script:RecordingEndTime
        Duration  = $duration
    }
}

function Add-InTUIRecordedAction {
    <#
    .SYNOPSIS
        Adds an action to the current recording.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter()]
        [hashtable]$Body,

        [Parameter()]
        [switch]$Beta
    )

    if (-not $script:RecordingEnabled) {
        return
    }

    # Only record write operations (POST, PATCH, DELETE)
    # GET requests are read-only and don't need to be replayed
    if ($Method -eq 'GET') {
        return
    }

    $action = @{
        Timestamp = [DateTime]::UtcNow.ToString('o')
        Method    = $Method
        Uri       = $Uri
        Beta      = [bool]$Beta
    }

    if ($Body) {
        $action['Body'] = $Body
    }

    $script:RecordedActions.Add($action)

    Write-InTUILog -Message "Action recorded" -Context @{
        Method = $Method
        Uri = $Uri
        ActionNumber = $script:RecordedActions.Count
    }
}

function Export-InTUIRecording {
    <#
    .SYNOPSIS
        Exports recorded actions to a PowerShell script.
    .PARAMETER Recording
        The recording object from Stop-InTUIRecording.
    .PARAMETER Path
        Output file path. Defaults to timestamped file in current directory.
    .PARAMETER IncludeConnection
        Include Connect-MgGraph call at the start.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Recording,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$IncludeConnection
    )

    if (-not $Recording -or $Recording.Actions.Count -eq 0) {
        Write-InTUILog -Level 'WARN' -Message "No actions to export"
        return $null
    }

    if (-not $Path) {
        $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd_HHmmss')
        $Path = Join-Path $script:InTUIConfig.DefaultExportPath "InTUI_Recording_$timestamp.ps1"
    }

    $scriptLines = [System.Collections.Generic.List[string]]::new()

    # Header
    $scriptLines.Add("# InTUI Recorded Script")
    $scriptLines.Add("# Generated: $([DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')) UTC")
    $scriptLines.Add("# Recording Duration: $([math]::Round($Recording.Duration)) seconds")
    $scriptLines.Add("# Actions: $($Recording.Actions.Count)")
    $scriptLines.Add("")
    $scriptLines.Add("#Requires -Modules Microsoft.Graph.Authentication")
    $scriptLines.Add("")

    if ($IncludeConnection) {
        $scriptLines.Add("# Connect to Microsoft Graph")
        $scriptLines.Add("Connect-MgGraph -Scopes @(")
        $scriptLines.Add("    'DeviceManagementManagedDevices.ReadWrite.All',")
        $scriptLines.Add("    'DeviceManagementApps.ReadWrite.All',")
        $scriptLines.Add("    'User.Read.All',")
        $scriptLines.Add("    'Group.Read.All'")
        $scriptLines.Add(") -NoWelcome")
        $scriptLines.Add("")
    }

    $scriptLines.Add("# Recorded Actions")
    $scriptLines.Add("`$results = @()")
    $scriptLines.Add("")

    $actionNum = 0
    foreach ($action in $Recording.Actions) {
        $actionNum++
        $scriptLines.Add("# Action $actionNum - $($action.Method) at $($action.Timestamp)")

        $baseUrl = if ($action.Beta) { 'https://graph.microsoft.com/beta' } else { 'https://graph.microsoft.com/v1.0' }
        $fullUri = if ($action.Uri -match '^https://') { $action.Uri } else { "$baseUrl/$($action.Uri.TrimStart('/'))" }

        $invokeParams = "`$params$actionNum = @{`n"
        $invokeParams += "    Uri    = '$fullUri'`n"
        $invokeParams += "    Method = '$($action.Method)'`n"
        $invokeParams += "    OutputType = 'PSObject'`n"

        if ($action.Body) {
            $bodyJson = $action.Body | ConvertTo-Json -Depth 10 -Compress
            $invokeParams += "    Body = '$bodyJson'`n"
            $invokeParams += "    ContentType = 'application/json'`n"
        }

        $invokeParams += "}"
        $scriptLines.Add($invokeParams)
        $scriptLines.Add("")
        $scriptLines.Add("try {")
        $scriptLines.Add("    `$result$actionNum = Invoke-MgGraphRequest @params$actionNum")
        $scriptLines.Add("    `$results += @{ Success = `$true; Action = $actionNum; Result = `$result$actionNum }")
        $scriptLines.Add("    Write-Host `"Action $actionNum completed successfully`" -ForegroundColor Green")
        $scriptLines.Add("}")
        $scriptLines.Add("catch {")
        $scriptLines.Add("    `$results += @{ Success = `$false; Action = $actionNum; Error = `$_.Exception.Message }")
        $scriptLines.Add("    Write-Host `"Action $actionNum failed: `$(`$_.Exception.Message)`" -ForegroundColor Red")
        $scriptLines.Add("}")
        $scriptLines.Add("")
    }

    $scriptLines.Add("# Summary")
    $scriptLines.Add("`$successCount = @(`$results | Where-Object { `$_.Success }).Count")
    $scriptLines.Add("`$failCount = @(`$results | Where-Object { -not `$_.Success }).Count")
    $scriptLines.Add("Write-Host `"Completed: `$successCount succeeded, `$failCount failed`"")
    $scriptLines.Add("")
    $scriptLines.Add("`$results")

    try {
        $scriptContent = $scriptLines -join "`n"
        Set-Content -Path $Path -Value $scriptContent -Encoding UTF8

        Write-InTUILog -Message "Recording exported" -Context @{
            Path = $Path
            ActionCount = $Recording.Actions.Count
        }

        return $Path
    }
    catch {
        Write-InTUILog -Level 'ERROR' -Message "Failed to export recording: $($_.Exception.Message)"
        return $null
    }
}

function Get-InTUIRecordingStatus {
    <#
    .SYNOPSIS
        Returns the current recording status.
    #>
    [CmdletBinding()]
    param()

    if (-not $script:RecordingEnabled) {
        return @{
            IsRecording = $false
            ActionCount = 0
            Duration    = 0
        }
    }

    $duration = ([DateTime]::UtcNow - $script:RecordingStartTime).TotalSeconds

    return @{
        IsRecording = $true
        ActionCount = $script:RecordedActions.Count
        Duration    = [math]::Round($duration)
        StartTime   = $script:RecordingStartTime
    }
}

function Show-InTUIRecordingMenu {
    <#
    .SYNOPSIS
        Shows the recording control menu.
    #>
    [CmdletBinding()]
    param()

    $status = Get-InTUIRecordingStatus

    if ($status.IsRecording) {
        $statusText = "[red]Recording in progress[/] - $($status.ActionCount) actions captured ($($status.Duration)s)"
    }
    else {
        $statusText = "[grey]Not recording[/]"
    }

    Clear-Host
    Show-InTUIHeader
    Show-InTUIBreadcrumb -Path @('Home', 'Script Recording')

    Write-SpectreHost $statusText
    Write-SpectreHost ""

    $choices = if ($status.IsRecording) {
        @(
            'Stop Recording and Export',
            'Stop Recording (Discard)',
            '─────────────',
            'Back'
        )
    }
    else {
        @(
            'Start Recording',
            '─────────────',
            'Back'
        )
    }

    $selection = Show-InTUIMenu -Title "[DarkOrange]Recording Options[/]" -Choices $choices

    switch ($selection) {
        'Start Recording' {
            if (Start-InTUIRecording) {
                Show-InTUISuccess "Recording started. Navigate and perform actions to record."
            }
            else {
                Show-InTUIWarning "Failed to start recording."
            }
            Read-InTUIKey
        }
        'Stop Recording and Export' {
            $recording = Stop-InTUIRecording
            if ($recording -and $recording.Actions.Count -gt 0) {
                $confirm = Show-InTUIConfirm -Message "[yellow]Include Connect-MgGraph in the script?[/]"
                $path = Export-InTUIRecording -Recording $recording -IncludeConnection:$confirm
                if ($path) {
                    Show-InTUISuccess "Recording exported to: $path"
                }
                else {
                    Show-InTUIWarning "No actions were recorded."
                }
            }
            else {
                Show-InTUIWarning "No actions were recorded."
            }
            Read-InTUIKey
        }
        'Stop Recording (Discard)' {
            $null = Stop-InTUIRecording
            $script:RecordedActions = $null
            Show-InTUISuccess "Recording discarded."
            Read-InTUIKey
        }
    }
}
