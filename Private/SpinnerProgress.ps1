function Write-InTUISpinner {
    <#
    .SYNOPSIS
        Rotating spinner with carriage return and elapsed time.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [int]$Frame = 0,

        [Parameter()]
        [System.Diagnostics.Stopwatch]$Stopwatch
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset
    $spinChars = @('|', '/', '-', '\')
    $spinChar = $spinChars[$Frame % $spinChars.Count]

    $elapsed = ''
    if ($Stopwatch) {
        $secs = [int]$Stopwatch.Elapsed.TotalSeconds
        $elapsed = " $($palette.Dim)(${secs}s)$reset"
    }

    $ansiMessage = ConvertFrom-InTUIMarkup -Text $Message
    Write-Host "`r$($palette.Blue)$spinChar$reset $ansiMessage$elapsed    " -NoNewline
}

function Write-InTUISpinnerComplete {
    <#
    .SYNOPSIS
        Clears spinner line and shows completion message.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Message = 'Done'
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset
    $clearWidth = [math]::Max(80, [Console]::WindowWidth - 1)

    Write-Host "`r$(' ' * $clearWidth)`r$($palette.Green)+$reset $Message"
}

function Invoke-InTUIWithSpinner {
    <#
    .SYNOPSIS
        Wraps a script block with spinner animation.
        Replaces Invoke-SpectreCommandWithStatus.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    $palette = Get-InTUIColorPalette

    # Start background job approach won't work for script-scope vars.
    # Use a simple spinner with polling.
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $frame = 0

    # Show initial spinner
    Write-InTUISpinner -Message $Title -Frame $frame -Stopwatch $sw

    # We can't run truly async in single-threaded PS, so we just run
    # the script block and show the spinner before/after.
    # For operations that support it, the spinner shows during execution.
    $result = $null
    try {
        $result = & $ScriptBlock
    }
    catch {
        $sw.Stop()
        Write-Host ""
        throw
    }

    $sw.Stop()
    Write-InTUISpinnerComplete -Message (Strip-InTUIMarkup -Text $Title)

    return $result
}
