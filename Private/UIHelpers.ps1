function Ensure-InTUIBufferSpace {
    <#
    .SYNOPSIS
        Scrolls the terminal buffer to ensure enough rows below the anchor for rendering.
    .DESCRIPTION
        When UI components render near the bottom of the terminal, SetCursorPosition
        calls past the buffer height silently fail or scroll content away. This function
        pre-scrolls the buffer to guarantee enough room, returning the adjusted anchor.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [int]$AnchorTop,

        [Parameter(Mandatory)]
        [int]$NeededRows
    )

    $bufferHeight = [Console]::BufferHeight
    $available = $bufferHeight - $AnchorTop

    if ($available -ge $NeededRows) { return $AnchorTop }

    # Scroll just enough, but keep the box title visible (3 rows above anchor)
    $scrollAmount = [math]::Min($NeededRows - $available, [math]::Max(0, $AnchorTop - 3))
    if ($scrollAmount -le 0) { return $AnchorTop }

    [Console]::SetCursorPosition(0, $bufferHeight - 1)
    for ($s = 0; $s -lt $scrollAmount; $s++) {
        [Console]::Write("`n")
    }
    return ($AnchorTop - $scrollAmount)
}

function Show-InTUIHeader {
    <#
    .SYNOPSIS
        Displays the InTUI header banner with gradient-bordered ASCII art.
    #>
    [CmdletBinding()]
    param(
        [string]$Subtitle
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    # Gradient-decorated top border
    $gradientTop = Get-InTUIGradientLine -Character ([char]0x2500) -Width 40
    Write-Host $gradientTop

    # ASCII art banner with gradient
    $bannerLines = @(
        '██╗███╗   ██╗████████╗██╗   ██╗██╗'
        '██║████╗  ██║╚══██╔══╝██║   ██║██║'
        '██║██╔██╗ ██║   ██║   ██║   ██║██║'
        '██║██║╚██╗██║   ██║   ██║   ██║██║'
        '██║██║ ╚████║   ██║   ╚██████╔╝██║'
        '╚═╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝'
    )
    foreach ($line in $bannerLines) {
        $gradientLine = Get-InTUIGradientString -Text $line
        Write-Host $gradientLine
    }

    Write-Host "$($palette.Dim)Intune Terminal User Interface$reset"
    Write-Host ""

    if ($script:Connected) {
        $tenant = if ($script:TenantId) { $script:TenantId } else { 'Unknown' }
        $account = if ($script:Account) { $script:Account } else { 'Unknown' }
        $envLabel = if ($script:CloudEnvironments -and $script:CloudEnvironment) {
            $script:CloudEnvironments[$script:CloudEnvironment].Label
        } else { 'Global' }
        Write-InTUIText "[grey]Env:[/] [cyan]$envLabel[/]"
        Write-InTUIText "[grey]Tenant:[/] [cyan]$tenant[/]"
        Write-InTUIText "[grey]Account:[/] [cyan]$account[/]"
    }

    if ($Subtitle) {
        Write-InTUIText "[grey]$Subtitle[/]"
    }

    # Gradient bottom border
    $gradientBottom = Get-InTUIGradientLine -Character ([char]0x2500) -Width 60
    Write-Host $gradientBottom
    Write-Host ""
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

    $separator = " [grey]>[/] "

    $pathItems = @()
    for ($i = 0; $i -lt $Path.Count; $i++) {
        $pathItems += "[blue]$($Path[$i])[/]"
    }

    $breadcrumb = $pathItems -join $separator
    Write-InTUIText $breadcrumb
    Write-Host ""
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
    Write-InTUIText $status
}

function Read-InTUIKey {
    <#
    .SYNOPSIS
        Reads a key press and returns the key info.
    #>
    Write-InTUIText "[grey]Press any key to continue...[/]"
    $null = [Console]::ReadKey($true)
}

function Show-InTUIMenu {
    <#
    .SYNOPSIS
        Displays a selection menu and returns the selected option string.
        Routes to arrow-key or classic menu based on capability.
        Returns the original choice string for backward-compatible switch matching.
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

    if ($script:HasArrowKeySupport) {
        $result = Show-InTUIMenuArrowSingle -Title $Title -Choices $Choices -PageSize $PageSize
    }
    else {
        $result = Show-InTUIMenuClassic -Title $Title -Choices $Choices
    }

    if ($result -eq 'Back') {
        # Escape pressed: find a Back/Cancel choice so the caller's switch exits naturally
        $backChoice = $Choices | Where-Object { $_ -match '^Back' } | Select-Object -Last 1
        return $backChoice  # $null if no back choice exists (e.g. main menu)
    }
    if ($result -is [int] -and $result -ge 0 -and $result -lt $Choices.Count) {
        return $Choices[$result]
    }
    return $null
}

function Show-InTUIMultiSelect {
    <#
    .SYNOPSIS
        Multi-selection menu wrapper. Returns selected choice strings.
        Replaces Read-SpectreMultiSelection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string[]]$Choices,

        [Parameter()]
        [int]$PageSize = 15
    )

    if ($script:HasArrowKeySupport) {
        $indices = Show-InTUIMenuArrowMulti -Title $Title -Choices $Choices -PageSize $PageSize
    }
    else {
        $indices = Show-InTUIMenuClassic -Title $Title -Choices $Choices -MultiSelect
    }

    if (-not $indices -or $indices.Count -eq 0) { return @() }

    $selected = @()
    foreach ($idx in $indices) {
        if ($idx -ge 0 -and $idx -lt $Choices.Count) {
            $selected += $Choices[$idx]
        }
    }
    return $selected
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

    Read-InTUIConfirmInput -Message $Message
}

function Show-InTUIPanel {
    <#
    .SYNOPSIS
        Displays content in a bordered panel.
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

    Render-InTUIPanel -Content $Content -Title $Title -BorderColor $BorderColor
}

function Show-InTUITable {
    <#
    .SYNOPSIS
        Creates and displays a formatted table.
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

    Render-InTUITable -Title $Title -Columns $Columns -Rows $Rows -BorderColor $BorderColor
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

    Invoke-InTUIWithSpinner -Title $Title -ScriptBlock $ScriptBlock
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

    Render-InTUIPanel -Content "[red]$Message[/]" -Title "[red]Error[/]" -BorderColor 'Red'
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

    Write-InTUIText "[green]+[/] $Message"
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

    Write-InTUIText "[yellow]![/] $Message"
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

    Write-InTUIText "[blue]*[/] $Message"
}

function Get-InTUIProgressBar {
    <#
    .SYNOPSIS
        Returns a text-based progress bar with markup.
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
        Displays a gradient-decorated section divider.
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
    $fullTitle = "$iconDisplay$Title"

    Write-Host ""
    $gradientLine = Get-InTUIGradientString -Text "--- $fullTitle ---"
    Write-Host $gradientLine
    Write-Host ""
}

function Get-InTUIStatusBadge {
    <#
    .SYNOPSIS
        Returns a colored status badge markup string.
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

    return "[$badgeColor]* $Status[/]"
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
        '*win32*'           { return '[blue]W[/]' }
        '*msi*'             { return '[blue]M[/]' }
        '*ios*'             { return '[grey]i[/]' }
        '*android*'         { return '[green]A[/]' }
        '*web*'             { return '[cyan]w[/]' }
        '*office*'          { return '[orange]O[/]' }
        '*microsoft*'       { return '[blue]M[/]' }
        default             { return '[grey]-[/]' }
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
        return '[yellow]*[/]'
    }
    elseif ($AccountEnabled -eq 'true') {
        return '[green]+[/]'
    }
    else {
        return '[red]-[/]'
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
        return '[cyan]SM[/]'
    }
    elseif ($SecurityEnabled -eq 'true') {
        return '[blue]S[/]'
    }
    elseif ($MailEnabled -eq 'true') {
        return '[cyan]@[/]'
    }
    elseif ($GroupType -match 'DynamicMembership') {
        return '[yellow]D[/]'
    }
    else {
        return '[grey]G[/]'
    }
}

function Show-InTUIBoxedText {
    <#
    .SYNOPSIS
        Displays text in a decorative Unicode box.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter()]
        [string]$Color = 'blue'
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    $colorAnsi = switch ($Color.ToLower()) {
        'blue'   { $palette.Blue }
        'green'  { $palette.Green }
        'red'    { $palette.Red }
        'yellow' { $palette.Yellow }
        'cyan'   { $palette.Cyan }
        default  { $palette.Blue }
    }

    $topLeft = [char]0x256D
    $topRight = [char]0x256E
    $bottomLeft = [char]0x2570
    $bottomRight = [char]0x256F
    $horizontal = [char]0x2500
    $vertical = [char]0x2502

    $padding = 2
    $textLength = Measure-InTUIDisplayWidth -Text (Strip-InTUIMarkup -Text $Text)
    $boxWidth = $textLength + ($padding * 2)

    $ansiText = ConvertFrom-InTUIMarkup -Text $Text
    Write-Host "$colorAnsi$topLeft$([string]::new($horizontal, $boxWidth))$topRight$reset"
    Write-Host "$colorAnsi$vertical$reset$(' ' * $padding)$ansiText$(' ' * $padding)$colorAnsi$vertical$reset"
    Write-Host "$colorAnsi$bottomLeft$([string]::new($horizontal, $boxWidth))$bottomRight$reset"
}

function Show-InTUISparkline {
    <#
    .SYNOPSIS
        Returns a sparkline chart markup string from an array of values.
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

function Protect-InTUIMarkup {
    <#
    .SYNOPSIS
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

# Keep backward-compatible alias
Set-Alias -Name ConvertTo-InTUISafeMarkup -Value Protect-InTUIMarkup
