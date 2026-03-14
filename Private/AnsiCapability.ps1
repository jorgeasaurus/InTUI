function Test-InTUIArrowKeySupport {
    <#
    .SYNOPSIS
        Checks if the terminal supports arrow-key interactive menus.
    #>
    [CmdletBinding()]
    param()

    # Require PS 7+
    if ($PSVersionTable.PSVersion.Major -lt 7) { return $false }

    # Must be interactive
    if (-not [Environment]::UserInteractive) { return $false }

    # Reject hosts that cannot support raw key reads (ISE, Notebook, etc.)
    if ($Host.Name -eq 'Windows PowerShell ISE Host') { return $false }

    # Verify Console.ReadKey won't throw (pipes, redirected IO, etc.)
    try {
        $null = [Console]::KeyAvailable
        return $true
    }
    catch {
        return $false
    }
}

function Test-InTUITrueColorSupport {
    <#
    .SYNOPSIS
        Checks if the terminal supports 24-bit true color.
    #>
    [CmdletBinding()]
    param()

    $colorTerm = $env:COLORTERM
    if ($colorTerm -eq 'truecolor' -or $colorTerm -eq '24bit') {
        return $true
    }

    # Windows Terminal and most modern terminals support it
    if ($env:WT_SESSION) { return $true }

    # VS Code integrated terminal
    if ($env:TERM_PROGRAM -eq 'vscode') { return $true }

    # iTerm2
    if ($env:TERM_PROGRAM -eq 'iTerm.app') { return $true }

    # Fall back to PS version check (PS 7+ on modern terminals generally supports it)
    if ($PSVersionTable.PSVersion.Major -ge 7) { return $true }

    return $false
}
