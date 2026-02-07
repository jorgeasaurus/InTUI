$script:LogFilePath = $null

function Initialize-InTUILog {
    <#
    .SYNOPSIS
        Initializes the InTUI verbose log file in the working directory.
    .DESCRIPTION
        Creates a timestamped log file in the current working directory.
        All subsequent calls to Write-InTUILog will append to this file.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$LogDirectory
    )

    if (-not $LogDirectory) {
        $LogDirectory = Get-Location -PSProvider FileSystem | Select-Object -ExpandProperty Path
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:LogFilePath = Join-Path $LogDirectory "InTUI_$timestamp.log"

    try {
        $header = @(
            "# InTUI Log - Started $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
            "# Version: $($script:InTUIVersion ?? 'Unknown')"
            "# PowerShell: $($PSVersionTable.PSVersion)"
            "# OS: $([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"
            '#' + ('-' * 79)
        ) -join "`n"

        Set-Content -Path $script:LogFilePath -Value $header -Encoding UTF8 -ErrorAction Stop
        Write-Verbose "InTUI log initialized: $($script:LogFilePath)"
    }
    catch {
        Write-Warning "Failed to initialize log file at $($script:LogFilePath): $($_.Exception.Message)"
        $script:LogFilePath = $null
    }
}

function Write-InTUILog {
    <#
    .SYNOPSIS
        Writes a verbose log entry to the InTUI log file.
    .DESCRIPTION
        Appends a structured log entry with timestamp, level, message, and optional
        context data to the log file initialized by Initialize-InTUILog.
    .PARAMETER Level
        Log level: INFO, WARN, ERROR, DEBUG. Defaults to INFO.
    .PARAMETER Message
        The log message.
    .PARAMETER Context
        Optional hashtable of contextual data to include in the log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Context
    )

    if (-not $script:LogFilePath) {
        return
    }

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $entry = "[$timestamp] [$Level] $Message"

    if ($Context -and $Context.Count -gt 0) {
        $contextParts = @()
        foreach ($key in $Context.Keys | Sort-Object) {
            $val = $Context[$key]
            if ($null -ne $val) {
                $contextParts += "$key=$val"
            }
        }
        if ($contextParts.Count -gt 0) {
            $entry += " | $($contextParts -join '; ')"
        }
    }

    try {
        Add-Content -Path $script:LogFilePath -Value $entry -Encoding UTF8
    }
    catch {
        # Silently fail - logging should never break the app
    }
}

function Get-InTUILogPath {
    <#
    .SYNOPSIS
        Returns the current log file path.
    #>
    [CmdletBinding()]
    param()

    return $script:LogFilePath
}
