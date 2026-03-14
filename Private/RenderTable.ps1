function Render-InTUITable {
    <#
    .SYNOPSIS
        Renders a table with column headers, auto-calculated widths, markup-aware
        cells, and box borders. Replaces Format-SpectreTable.
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

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset
    $innerWidth = Get-InTUIConsoleInnerWidth

    $borderAnsi = switch ($BorderColor.ToLower()) {
        'blue'   { $palette.Blue }
        'green'  { $palette.Green }
        'red'    { $palette.Red }
        'yellow' { $palette.Yellow }
        'cyan'   { $palette.Cyan }
        default  { $palette.Blue }
    }

    $colCount = $Columns.Count

    # Calculate column widths based on header and data (using display width)
    $colWidths = [int[]]::new($colCount)
    for ($c = 0; $c -lt $colCount; $c++) {
        $colWidths[$c] = Measure-InTUIDisplayWidth -Text (Strip-InTUIMarkup -Text $Columns[$c])
    }
    foreach ($row in $Rows) {
        for ($c = 0; $c -lt $colCount; $c++) {
            $cellText = if ($c -lt $row.Count) { [string]$row[$c] } else { '' }
            $plainLen = Measure-InTUIDisplayWidth -Text (Strip-InTUIMarkup -Text $cellText)
            if ($plainLen -gt $colWidths[$c]) {
                $colWidths[$c] = $plainLen
            }
        }
    }

    # Clamp total width
    $separators = ($colCount - 1) * 3  # " | " between columns
    $borders = 4  # "| " + " |"
    $totalContent = ($colWidths | Measure-Object -Sum).Sum + $separators + $borders
    $maxWidth = $innerWidth

    if ($totalContent -gt $maxWidth) {
        # Proportionally shrink columns
        $available = $maxWidth - $separators - $borders
        $currentTotal = ($colWidths | Measure-Object -Sum).Sum
        for ($c = 0; $c -lt $colCount; $c++) {
            $colWidths[$c] = [Math]::Max(4, [int]($colWidths[$c] * $available / $currentTotal))
        }
    }

    $tableWidth = ($colWidths | Measure-Object -Sum).Sum + $separators + $borders

    # Box chars
    $topLeft     = [char]0x256D
    $topRight    = [char]0x256E
    $bottomLeft  = [char]0x2570
    $bottomRight = [char]0x256F
    $horizontal  = [char]0x2500
    $vertical    = [char]0x2502

    # Title
    $plainTitle = Strip-InTUIMarkup -Text $Title
    $ansiTitle = ConvertFrom-InTUIMarkup -Text $Title
    $titleDisplayWidth = Measure-InTUIDisplayWidth -Text $plainTitle
    $titleLineLen = $tableWidth - 4 - $titleDisplayWidth
    $leftLine = [Math]::Max(1, [int]([Math]::Floor($titleLineLen / 2)))
    $rightLine = [Math]::Max(1, $titleLineLen - $leftLine)
    Write-Host "$borderAnsi$topLeft$([string]::new($horizontal, $leftLine))$reset $ansiTitle $borderAnsi$([string]::new($horizontal, $rightLine))$topRight$reset"

    # Header row
    $headerCells = @()
    for ($c = 0; $c -lt $colCount; $c++) {
        $plainCol = Strip-InTUIMarkup -Text $Columns[$c]
        $colDisplayWidth = Measure-InTUIDisplayWidth -Text $plainCol
        $pad = [Math]::Max(0, $colWidths[$c] - $colDisplayWidth)
        $headerCells += "$($palette.Bold)$($palette.White)$plainCol$(' ' * $pad)$reset"
    }
    $headerLine = $headerCells -join " $($palette.Dim)$vertical$reset "
    Write-Host "$borderAnsi$vertical$reset $headerLine $borderAnsi$vertical$reset"

    # Header underline
    $underlineParts = @()
    for ($c = 0; $c -lt $colCount; $c++) {
        $underlineParts += [string]::new($horizontal, $colWidths[$c])
    }
    $underline = $underlineParts -join "$horizontal$([char]0x253C)$horizontal"
    Write-Host "$borderAnsi$vertical$reset$horizontal$underline$horizontal$borderAnsi$vertical$reset"

    # Data rows
    foreach ($row in $Rows) {
        $cells = @()
        for ($c = 0; $c -lt $colCount; $c++) {
            $cellText = if ($c -lt $row.Count) { [string]$row[$c] } else { '' }
            $plainCell = Strip-InTUIMarkup -Text $cellText
            $ansiCell = ConvertFrom-InTUIMarkup -Text $cellText
            $cellDisplayWidth = Measure-InTUIDisplayWidth -Text $plainCell

            if ($cellDisplayWidth -gt $colWidths[$c]) {
                # Walk the plain text to find the cut point
                $cutLen = 0
                $cutWidth = 0
                $maxCut = $colWidths[$c] - 3
                for ($ci = 0; $ci -lt $plainCell.Length; $ci++) {
                    $charWidth = Measure-InTUIDisplayWidth -Text ([string]$plainCell[$ci])
                    if (($cutWidth + $charWidth) -gt $maxCut) { break }
                    $cutWidth += $charWidth
                    $cutLen++
                }
                $plainCell = $plainCell.Substring(0, [Math]::Max(1, $cutLen)) + '...'
                $ansiCell = $plainCell
                $cellDisplayWidth = $cutWidth + 3
            }

            $pad = [Math]::Max(0, $colWidths[$c] - $cellDisplayWidth)
            $cells += "$ansiCell$reset$(' ' * $pad)"
        }
        $rowLine = $cells -join " $($palette.Dim)$vertical$reset "
        Write-Host "$borderAnsi$vertical$reset $rowLine $borderAnsi$vertical$reset"
    }

    # Bottom border
    Write-Host "$borderAnsi$bottomLeft$([string]::new($horizontal, ($tableWidth - 2)))$bottomRight$reset"
}

function Show-InTUISortableTable {
    <#
    .SYNOPSIS
        Wraps Render-InTUITable with interactive column sorting.
        Press S to sort, then select a column. Toggles asc/desc.
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

    $sortColIndex = -1
    $sortAsc = $true
    $currentRows = $Rows
    $currentColumns = $Columns.Clone()

    while ($true) {
        Clear-Host
        Show-InTUIHeader

        Render-InTUITable -Title $Title -Columns $currentColumns -Rows $currentRows -BorderColor $BorderColor

        Write-InTUIText "[grey]S: Sort | Any other key: continue[/]"

        $keyInfo = [Console]::ReadKey($true)
        if ($keyInfo.KeyChar -eq 's' -or $keyInfo.KeyChar -eq 'S') {
            $colChoices = @($Columns) + @('Cancel')
            $colSelection = Show-InTUIMenu -Title "[blue]Sort by column[/]" -Choices $colChoices

            if ($colSelection -ne 'Cancel') {
                $newIndex = [Array]::IndexOf($Columns, $colSelection)
                if ($newIndex -ge 0) {
                    if ($newIndex -eq $sortColIndex) {
                        $sortAsc = -not $sortAsc
                    }
                    else {
                        $sortColIndex = $newIndex
                        $sortAsc = $true
                    }

                    # Sort rows by the selected column (strip markup for comparison)
                    $currentRows = @($Rows | Sort-Object {
                        $val = if ($sortColIndex -lt $_.Count) { [string]$_[$sortColIndex] } else { '' }
                        $plain = Strip-InTUIMarkup -Text $val

                        # Try numeric sort
                        $num = 0
                        if ([double]::TryParse(($plain -replace '[%,]', ''), [ref]$num)) {
                            $num
                        }
                        else {
                            $plain
                        }
                    } -Descending:(-not $sortAsc))

                    # Update column headers with sort indicator
                    $currentColumns = $Columns.Clone()
                    $arrow = if ($sortAsc) { [char]0x25B2 } else { [char]0x25BC }
                    $currentColumns[$sortColIndex] = "$($Columns[$sortColIndex]) $arrow"
                }
            }
        }
        else {
            break
        }
    }
}
