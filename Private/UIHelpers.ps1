function Show-InTUIHeader {
    <#
    .SYNOPSIS
        Displays the InTUI header banner.
    #>
    [CmdletBinding()]
    param(
        [string]$Subtitle
    )

    Write-SpectreRule -Title "[blue bold]InTUI[/] [grey]- Intune Terminal UI[/]" -Color Blue

    if ($script:Connected) {
        $tenant = if ($script:TenantId) { $script:TenantId } else { 'Unknown' }
        $account = if ($script:Account) { $script:Account } else { 'Unknown' }
        $envLabel = if ($script:CloudEnvironments -and $script:CloudEnvironment) {
            $script:CloudEnvironments[$script:CloudEnvironment].Label
        } else { 'Global' }
        Write-SpectreHost "[grey]Tenant:[/] [cyan]$tenant[/] [grey]|[/] [grey]Account:[/] [cyan]$account[/] [grey]|[/] [grey]Environment:[/] [cyan]$envLabel[/]"
    }

    if ($Subtitle) {
        Write-SpectreHost "[grey]$Subtitle[/]"
    }

    Write-SpectreHost ""
}

function Show-InTUIBreadcrumb {
    <#
    .SYNOPSIS
        Displays a breadcrumb navigation bar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path
    )

    $breadcrumb = ($Path | ForEach-Object { "[blue]$_[/]" }) -join " [grey]>[/] "
    Write-SpectreHost $breadcrumb
    Write-SpectreHost ""
}

function Show-InTUIStatusBar {
    <#
    .SYNOPSIS
        Displays a status bar with counts.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [int]$Total = 0,

        [Parameter()]
        [int]$Showing = 0,

        [Parameter()]
        [string]$FilterText
    )

    $status = "[grey]Showing [white]$Showing[/] of [white]$Total[/] items[/]"
    if ($FilterText) {
        $status += " [grey]| Filter: [yellow]$FilterText[/][/]"
    }
    Write-SpectreHost $status
}

function Read-InTUIKey {
    <#
    .SYNOPSIS
        Reads a key press and returns the key info.
    #>
    Write-SpectreHost "[grey]Press any key to continue...[/]"
    $null = [Console]::ReadKey($true)
}

function Show-InTUIMenu {
    <#
    .SYNOPSIS
        Displays a selection menu using Spectre Console and returns the selected option.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string[]]$Choices,

        [Parameter()]
        [string]$Color = 'Blue',

        [Parameter()]
        [int]$PageSize = 15
    )

    Read-SpectreSelection -Title $Title -Choices $Choices -Color $Color -PageSize $PageSize
}

function Show-InTUIConfirm {
    <#
    .SYNOPSIS
        Shows a confirmation prompt.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Read-SpectreConfirm -Prompt $Message
}

function Show-InTUIPanel {
    <#
    .SYNOPSIS
        Displays content in a Spectre panel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter()]
        [string]$BorderColor = 'Blue'
    )

    Format-SpectrePanel -Data $Content -Title $Title -Color $BorderColor | Out-SpectreHost
}

function Show-InTUITable {
    <#
    .SYNOPSIS
        Creates and displays a formatted Spectre table.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string[]]$Columns,

        [Parameter(Mandatory)]
        [array]$Rows,

        [Parameter()]
        [string]$BorderColor = 'Blue'
    )

    $tableData = [System.Collections.Generic.List[PSCustomObject]]::new()
    foreach ($row in $Rows) {
        $obj = [ordered]@{}
        for ($i = 0; $i -lt $Columns.Count; $i++) {
            $obj[$Columns[$i]] = if ($i -lt $row.Count) { $row[$i] } else { '' }
        }
        $tableData.Add([PSCustomObject]$obj)
    }

    $tableData | Format-SpectreTable -Title $Title -Color $BorderColor -AllowMarkup
}

function Show-InTUILoading {
    <#
    .SYNOPSIS
        Shows a loading spinner while executing a script block.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock
    )

    Invoke-SpectreCommandWithStatus -Title $Title -ScriptBlock $ScriptBlock
}

function Show-InTUIError {
    <#
    .SYNOPSIS
        Displays an error message in a styled panel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Format-SpectrePanel -Data "[red]$Message[/]" -Title "[red]Error[/]" -Color Red | Out-SpectreHost
}

function Show-InTUISuccess {
    <#
    .SYNOPSIS
        Displays a success message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-SpectreHost "[green]✓[/] $Message"
}

function Show-InTUIWarning {
    <#
    .SYNOPSIS
        Displays a warning message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-SpectreHost "[yellow]⚠[/] $Message"
}

function Get-InTUIConfigProfileType {
    <#
    .SYNOPSIS
        Maps a device configuration @odata.type to a friendly name and platform.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$ODataType
    )

    if ([string]::IsNullOrEmpty($ODataType)) {
        return @{ Platform = 'Unknown'; FriendlyName = 'Unknown' }
    }

    switch -Wildcard ($ODataType) {
        '*windows10General*'            { return @{ Platform = 'Windows'; FriendlyName = 'General' } }
        '*windows10Custom*'             { return @{ Platform = 'Windows'; FriendlyName = 'Custom' } }
        '*windows10EndpointProtection*' { return @{ Platform = 'Windows'; FriendlyName = 'Endpoint Protection' } }
        '*windowsUpdateForBusiness*'    { return @{ Platform = 'Windows'; FriendlyName = 'Update Ring' } }
        '*iosGeneral*'                  { return @{ Platform = 'iOS'; FriendlyName = 'General' } }
        '*iosCustom*'                   { return @{ Platform = 'iOS'; FriendlyName = 'Custom' } }
        '*macOSGeneral*'                { return @{ Platform = 'macOS'; FriendlyName = 'General' } }
        '*macOSCustom*'                 { return @{ Platform = 'macOS'; FriendlyName = 'Custom' } }
        '*androidGeneral*'              { return @{ Platform = 'Android'; FriendlyName = 'General' } }
        '*androidCustom*'               { return @{ Platform = 'Android'; FriendlyName = 'Custom' } }
        default {
            $rawType = $ODataType -replace '#microsoft\.graph\.', ''
            return @{ Platform = 'Unknown'; FriendlyName = $rawType }
        }
    }
}
