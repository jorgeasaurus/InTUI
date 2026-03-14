<#
.SYNOPSIS
    tmux-based TUI test harness. Provides Playwright-style helpers for testing
    interactive terminal menus by launching them in detached tmux sessions,
    sending keystrokes, and capturing screen snapshots as plain text.
.DESCRIPTION
    Requires: tmux (pre-installed on macOS and most Linux CI runners).
    All functions are designed to be called from Pester tests.
#>

function New-TUISession {
    <#
    .SYNOPSIS
        Launches a PowerShell command inside a detached tmux session.
        Returns the session name (used as a handle for all other functions).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Command,

        [Parameter()]
        [int]$Width = 120,

        [Parameter()]
        [int]$Height = 40,

        [Parameter()]
        [int]$WaitMs = 2000
    )

    $name = "intui-test-$PID-$(Get-Random)"

    # Launch in detached tmux session with fixed dimensions.
    # remain-on-exit keeps the pane readable after the script completes,
    # so assertions on final output (e.g. "SELECTED:Devices") still work.
    $tmuxCmd = "pwsh -NoProfile -Command '$($Command -replace "'","''")'"
    & tmux new-session -d -s $name -x $Width -y $Height $tmuxCmd
    & tmux set-option -t $name remain-on-exit on 2>$null

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create tmux session '$name'"
    }

    # Wait for initial render
    Start-Sleep -Milliseconds $WaitMs
    return $name
}

function Send-TUIKey {
    <#
    .SYNOPSIS
        Sends one or more keystrokes to a tmux session.
        Key names follow tmux send-keys conventions:
        Up, Down, Left, Right, Enter, Escape, Space, Tab, etc.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Session,

        [Parameter(Mandatory)]
        [string[]]$Keys,

        [Parameter()]
        [int]$DelayMs = 200
    )

    foreach ($k in $Keys) {
        & tmux send-keys -t $Session $k
        Start-Sleep -Milliseconds $DelayMs
    }
}

function Get-TUISnapshot {
    <#
    .SYNOPSIS
        Captures the current terminal screen content as a plain-text string.
        ANSI escape codes are stripped by tmux capture-pane.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Session
    )

    $lines = & tmux capture-pane -t $Session -p
    return ($lines -join "`n")
}

function Wait-TUIContent {
    <#
    .SYNOPSIS
        Polls the terminal screen until a regex pattern appears or timeout.
        Returns the snapshot that matched, or throws on timeout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Session,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter()]
        [int]$TimeoutMs = 5000,

        [Parameter()]
        [int]$PollMs = 150
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $snap = Get-TUISnapshot -Session $Session
        if ($snap -match $Pattern) {
            return $snap
        }
        Start-Sleep -Milliseconds $PollMs
    }
    throw "Timed out after ${TimeoutMs}ms waiting for pattern: $Pattern"
}

function Wait-TUIContentGone {
    <#
    .SYNOPSIS
        Polls until a pattern disappears from the screen, or throws on timeout.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Session,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter()]
        [int]$TimeoutMs = 5000,

        [Parameter()]
        [int]$PollMs = 150
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while ($sw.ElapsedMilliseconds -lt $TimeoutMs) {
        $snap = Get-TUISnapshot -Session $Session
        if ($snap -notmatch $Pattern) {
            return $snap
        }
        Start-Sleep -Milliseconds $PollMs
    }
    throw "Timed out after ${TimeoutMs}ms waiting for pattern to disappear: $Pattern"
}

function Close-TUISession {
    <#
    .SYNOPSIS
        Kills the tmux session, cleaning up the test process.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Session
    )

    & tmux kill-session -t $Session 2>$null
}

function Assert-TUISessionAlive {
    <#
    .SYNOPSIS
        Returns $true if the tmux session is still running.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Session
    )

    & tmux has-session -t $Session 2>$null
    return ($LASTEXITCODE -eq 0)
}
