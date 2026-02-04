function Show-InTUIHeader {
    <#
    .SYNOPSIS
        Displays the InTUI header banner.
    #>
    [CmdletBinding()]
    param(
        [string]$Subtitle
    )

    $rule = New-SpectreRule -Title "[blue bold]InTUI[/] [grey]- Intune Terminal UI[/]" -Color Blue
    Write-SpectreHost $rule

    if ($script:Connected) {
        $tenant = if ($script:TenantId) { $script:TenantId } else { 'Unknown' }
        $account = if ($script:Account) { $script:Account } else { 'Unknown' }
        Write-SpectreHost "[grey]Tenant:[/] [cyan]$tenant[/] [grey]|[/] [grey]Account:[/] [cyan]$account[/]"
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
        [string]$Color = 'Blue'
    )

    $selection = Read-SpectreSelection -Title $Title -Choices $Choices -Color $Color
    return $selection
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

    $result = Read-SpectreConfirm -Prompt $Message
    return $result
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
        [string]$BorderColor = 'Blue',

        [Parameter()]
        [switch]$Expand
    )

    $panel = Format-SpectrePanel -Title $Title -Content $Content -Color $BorderColor
    if ($Expand) {
        $panel = $panel
    }
    Write-SpectreHost $panel
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

    $tableData = @()
    foreach ($row in $Rows) {
        $obj = [ordered]@{}
        for ($i = 0; $i -lt $Columns.Count; $i++) {
            $obj[$Columns[$i]] = if ($i -lt $row.Count) { $row[$i] } else { '' }
        }
        $tableData += [PSCustomObject]$obj
    }

    $tableData | Format-SpectreTable -Title $Title -Color $BorderColor
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

    Format-SpectrePanel -Title "[red]Error[/]" -Content "[red]$Message[/]" -Color Red | Write-SpectreHost
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

function ConvertTo-InTUITableData {
    <#
    .SYNOPSIS
        Converts an array of PSObjects to table-ready format.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Data,

        [Parameter(Mandatory)]
        [hashtable[]]$ColumnMap
    )

    $rows = @()
    foreach ($item in $Data) {
        $row = @()
        foreach ($col in $ColumnMap) {
            $value = $item
            foreach ($prop in $col.Property.Split('.')) {
                if ($null -ne $value) {
                    $value = $value.$prop
                }
            }

            if ($col.Transform) {
                $value = & $col.Transform $value
            }

            $row += if ($null -ne $value) { [string]$value } else { 'N/A' }
        }
        $rows += , $row
    }

    return $rows
}
