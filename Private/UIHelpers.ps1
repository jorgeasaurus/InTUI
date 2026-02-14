function Show-InTUIHeader {
    <#
    .SYNOPSIS
        Displays the InTUI header banner with ASCII art.
    #>
    [CmdletBinding()]
    param(
        [string]$Subtitle
    )

    # ASCII art banner
    $banner = @"
[blue]  ___       _____  _   _  ___ [/]
[blue] |_ _|_ __ |_   _|| | | ||_ _|[/]
[blue]  | || '_ \  | |  | | | | | | [/]
[blue]  | || | | | | |  | |_| | | | [/]
[blue] |___|_| |_| |_|   \___/ |___|[/]
"@
    Write-SpectreHost $banner
    Write-SpectreHost "[grey dim]Intune Terminal User Interface[/]"
    Write-SpectreHost ""

    if ($script:Connected) {
        $tenant = if ($script:TenantId) { $script:TenantId } else { 'Unknown' }
        $account = if ($script:Account) { $script:Account } else { 'Unknown' }
        $envLabel = if ($script:CloudEnvironments -and $script:CloudEnvironment) {
            $script:CloudEnvironments[$script:CloudEnvironment].Label
        } else { 'Global' }
        Write-SpectreHost "[grey]$([char]0x25CF)[/] [grey]Tenant:[/] [cyan]$tenant[/]  [grey]$([char]0x25CF)[/] [grey]Account:[/] [cyan]$account[/]  [grey]$([char]0x25CF)[/] [grey]Env:[/] [cyan]$envLabel[/]"
    }

    if ($Subtitle) {
        Write-SpectreHost "[grey]$Subtitle[/]"
    }

    Write-SpectreHost "[grey dim]$(([string][char]0x2500) * 60)[/]"
    Write-SpectreHost ""
}

function Show-InTUIBreadcrumb {
    <#
    .SYNOPSIS
        Displays a breadcrumb navigation bar with visual separator.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Path
    )

    $separator = " [grey]$([char]0x25B8)[/] "
    $homeIcon = "[cyan]$([char]0x2302)[/]"

    $pathItems = @()
    for ($i = 0; $i -lt $Path.Count; $i++) {
        if ($i -eq 0) {
            $pathItems += "$homeIcon [blue]$($Path[$i])[/]"
        }
        else {
            $pathItems += "[blue]$($Path[$i])[/]"
        }
    }

    $breadcrumb = $pathItems -join $separator
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

function Get-InTUIChoiceMap {
    <#
    .SYNOPSIS
        Ensures menu choices are unique and returns an index map.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Choices
    )

    $counts = @{}
    $uniqueChoices = [System.Collections.Generic.List[string]]::new()
    $indexMap = @{}

    for ($i = 0; $i -lt $Choices.Count; $i++) {
        $choice = $Choices[$i]
        if (-not $counts.ContainsKey($choice)) {
            $counts[$choice] = 0
        }
        $counts[$choice]++

        $suffix = if ($counts[$choice] -gt 1) { " [grey](#$($counts[$choice]))[/]" } else { '' }
        $uniqueChoice = "$choice$suffix"
        $uniqueChoices.Add($uniqueChoice)
        $indexMap[$uniqueChoice] = $i
    }

    return @{ Choices = $uniqueChoices.ToArray(); IndexMap = $indexMap }
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

    Write-SpectreHost "[yellow]$([char]0x26A0)[/] $Message"
}

function Show-InTUIInfo {
    <#
    .SYNOPSIS
        Displays an info message.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    Write-SpectreHost "[blue]$([char]0x2139)[/] $Message"
}

function Get-InTUIProgressBar {
    <#
    .SYNOPSIS
        Returns a text-based progress bar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double]$Percentage,

        [Parameter()]
        [int]$Width = 20,

        [Parameter()]
        [string]$FilledColor = 'green',

        [Parameter()]
        [string]$EmptyColor = 'grey'
    )

    $percentage = [Math]::Max(0, [Math]::Min(100, $Percentage))
    $filled = [int][Math]::Floor(($percentage / 100) * $Width)
    $empty = [int]($Width - $filled)

    $filledChar = [string][char]0x2588  # Full block
    $emptyChar = [string][char]0x2591   # Light shade

    $bar = "[$FilledColor]$($filledChar * $filled)[/][$EmptyColor]$($emptyChar * $empty)[/]"
    return $bar
}

function Show-InTUISectionHeader {
    <#
    .SYNOPSIS
        Displays a decorative section header.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter()]
        [string]$Color = 'blue',

        [Parameter()]
        [string]$Icon
    )

    $iconDisplay = if ($Icon) { "$Icon " } else { "" }
    $line = [char]0x2550 * 3
    Write-SpectreHost ""
    Write-SpectreHost "[$Color]$line $iconDisplay$Title $line[/]"
    Write-SpectreHost ""
}

function Get-InTUIStatusBadge {
    <#
    .SYNOPSIS
        Returns a colored status badge.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Status,

        [Parameter()]
        [string]$Color
    )

    $badgeColor = if ($Color) { $Color } else {
        switch -Wildcard ($Status.ToLower()) {
            '*success*'    { 'green' }
            '*compli*'     { 'green' }
            '*enabled*'    { 'green' }
            '*active*'     { 'green' }
            '*installed*'  { 'green' }
            '*fail*'       { 'red' }
            '*error*'      { 'red' }
            '*disabled*'   { 'red' }
            '*noncompliant*' { 'red' }
            '*warning*'    { 'yellow' }
            '*pending*'    { 'yellow' }
            '*grace*'      { 'yellow' }
            '*processing*' { 'cyan' }
            default        { 'grey' }
        }
    }

    return "[$badgeColor]$([char]0x25CF) $Status[/]"
}

function Get-InTUIAppIcon {
    <#
    .SYNOPSIS
        Returns an icon based on app type.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$AppType
    )

    switch -Wildcard ($AppType) {
        '*win32*'           { return '[blue]$([char]0x2B1B)[/]' }
        '*msi*'             { return '[blue]$([char]0x229E)[/]' }
        '*ios*'             { return '[grey]$([char]0x25C9)[/]' }
        '*android*'         { return '[green]$([char]0x25B2)[/]' }
        '*web*'             { return '[cyan]$([char]0x1F310)[/]' }
        '*office*'          { return '[orange1]$([char]0x25A3)[/]' }
        '*microsoft*'       { return '[blue]$([char]0x25A0)[/]' }
        default             { return '[grey]$([char]0x25A1)[/]' }
    }
}

function Get-InTUIUserIcon {
    <#
    .SYNOPSIS
        Returns a user icon with optional status.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$AccountEnabled = 'true',

        [Parameter()]
        [switch]$IsAdmin
    )

    if ($IsAdmin) {
        return '[yellow]$([char]0x2605)[/]'  # Star for admin
    }
    elseif ($AccountEnabled -eq 'true') {
        return '[green]$([char]0x25CF)[/]'   # Filled circle for enabled
    }
    else {
        return '[red]$([char]0x25CB)[/]'     # Empty circle for disabled
    }
}

function Get-InTUIGroupIcon {
    <#
    .SYNOPSIS
        Returns a group icon based on type.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$GroupType,

        [Parameter()]
        [string]$SecurityEnabled,

        [Parameter()]
        [string]$MailEnabled
    )

    if ($SecurityEnabled -eq 'true' -and $MailEnabled -eq 'true') {
        return '[cyan]$([char]0x29C9)[/]'   # Mail-enabled security group
    }
    elseif ($SecurityEnabled -eq 'true') {
        return '[blue]$([char]0x26E8)[/]'      # Security group (shield)
    }
    elseif ($MailEnabled -eq 'true') {
        return '[cyan]$([char]0x2709)[/]'      # Distribution group (envelope)
    }
    elseif ($GroupType -match 'DynamicMembership') {
        return '[yellow]$([char]0x21BB)[/]'    # Dynamic group (circular arrow)
    }
    else {
        return '[grey]$([char]0x25A6)[/]'      # Generic group
    }
}

function Show-InTUIBoxedText {
    <#
    .SYNOPSIS
        Displays text in a decorative box.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter()]
        [string]$Color = 'blue'
    )

    $topLeft = [char]0x256D
    $topRight = [char]0x256E
    $bottomLeft = [char]0x2570
    $bottomRight = [char]0x256F
    $horizontal = [char]0x2500
    $vertical = [char]0x2502

    $padding = 2
    $textLength = ($Text -replace '\[[^\]]+\]', '').Length
    $boxWidth = $textLength + ($padding * 2)

    Write-SpectreHost "[$Color]$topLeft$($horizontal * $boxWidth)$topRight[/]"
    Write-SpectreHost "[$Color]$vertical[/]$(' ' * $padding)$Text$(' ' * $padding)[$Color]$vertical[/]"
    Write-SpectreHost "[$Color]$bottomLeft$($horizontal * $boxWidth)$bottomRight[/]"
}

function Show-InTUISparkline {
    <#
    .SYNOPSIS
        Displays a sparkline chart from an array of values.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [double[]]$Values,

        [Parameter()]
        [string]$Color = 'cyan'
    )

    $blocks = @([char]0x2581, [char]0x2582, [char]0x2583, [char]0x2584, [char]0x2585, [char]0x2586, [char]0x2587, [char]0x2588)

    $min = ($Values | Measure-Object -Minimum).Minimum
    $max = ($Values | Measure-Object -Maximum).Maximum
    $range = $max - $min

    if ($range -eq 0) { $range = 1 }

    $sparkline = ""
    foreach ($value in $Values) {
        $normalized = [Math]::Floor((($value - $min) / $range) * 7)
        $sparkline += $blocks[$normalized]
    }

    return "[$Color]$sparkline[/]"
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

function ConvertTo-InTUISafeMarkup {
    <#
    .SYNOPSIS
        Escapes text for safe use in Spectre Console markup.
    .DESCRIPTION
        Escapes brackets so they are displayed literally instead of being
        interpreted as markup tags.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }

    return $Text -replace '\[', '[[' -replace '\]', ']]'
}
