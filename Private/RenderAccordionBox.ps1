function Render-InTUIAccordionBox {
    <#
    .SYNOPSIS
        Renders accordion menu items inside a box with in-place redraw.
    .DESCRIPTION
        Draws parent (section) and child (action) rows inside a Unicode box
        using Console.SetCursorPosition for flicker-free updates. Expanded
        parents show their children inline. Supports a single expanded
        section at a time.

        Visual indicators:
        - Collapsed parent: right-pointing triangle with child count
        - Expanded parent: down-pointing triangle in Teal
        - IsDirect parent: right arrow in Peach
        - Child item: angle bracket in Subtext
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory)]
        [int]$SelectedIndex,

        [Parameter(Mandatory)]
        [int]$AnchorTop,

        [Parameter()]
        [int]$PreviousRowCount = 0
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    $innerWidth = Get-InTUIConsoleInnerWidth
    $border = [char]0x2502
    $hLine = [char]0x2500

    $collapsedChar = [char]0x25B8  # right-pointing triangle
    $expandedChar  = [char]0x25BE  # down-pointing triangle
    $directChar    = [char]0x2192  # right arrow
    $childChar     = [char]0x203A  # single right-pointing angle quotation mark

    $fitText = {
        param([string]$Text)
        if ($null -eq $Text) { return '' }
        if ($Text.Length -le $innerWidth) { return $Text }
        if ($innerWidth -le 3) { return $Text.Substring(0, $innerWidth) }
        return $Text.Substring(0, $innerWidth - 3) + '...'
    }

    $row = $AnchorTop

    # Empty line inside box
    $emptyLine = '  {0}{1}{2}{3}{4}' -f $palette.SurfaceFg, $border, (' ' * $innerWidth), $border, $reset
    [Console]::SetCursorPosition(0, $row)
    [Console]::Write($emptyLine)
    $row++

    # Render each row
    for ($i = 0; $i -lt $Rows.Count; $i++) {
        [Console]::SetCursorPosition(0, $row)

        $currentRow = $Rows[$i]
        $isHighlighted = ($i -eq $SelectedIndex)
        # Strip any [color]...[/] markup -- the renderer controls colors
        $rowLabel = Strip-InTUIMarkup -Text $currentRow.Label

        if ($currentRow.Type -eq 'parent') {
            $sectionNum = $currentRow.SectionIndex + 1

            if ($currentRow.IsDirect) {
                $indicator = $directChar
            }
            elseif ($currentRow.Expanded) {
                $indicator = $expandedChar
            }
            else {
                $indicator = $collapsedChar
            }

            # Build label with child count for collapsed expandable sections
            $displayLabel = $rowLabel
            if (-not $currentRow.IsDirect -and -not $currentRow.Expanded -and $currentRow.ChildCount -gt 0) {
                $displayLabel = '{0} ({1})' -f $rowLabel, $currentRow.ChildCount
            }

            if ($isHighlighted) {
                $chevron = [char]0x276F
                $itemText = '  {0} {1}  {2} {3}' -f $chevron, $sectionNum, $indicator, $displayLabel
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}{6}{7}' -f $palette.SurfaceFg, $border, $palette.BgSelect, $palette.Mauve, $palette.Bold, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
            elseif ($currentRow.Expanded) {
                $itemText = '     {0}  {1} {2}' -f $sectionNum, $indicator, $displayLabel
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Teal, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
            elseif ($currentRow.IsDirect) {
                $itemText = '     {0}  {1} {2}' -f $sectionNum, $indicator, $displayLabel
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Peach, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
            else {
                $itemText = '     {0}  {1} {2}' -f $sectionNum, $indicator, $displayLabel
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Text, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
        }
        else {
            # Child row
            $childNum = '{0}.{1}' -f ($currentRow.SectionIndex + 1), ($currentRow.ChildIndex + 1)

            if ($isHighlighted) {
                $chevron = [char]0x276F
                $itemText = '    {0} {1}  {2} {3}' -f $chevron, $childNum, $childChar, $rowLabel
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}{6}{7}' -f $palette.SurfaceFg, $border, $palette.BgSelect, $palette.Mauve, $palette.Bold, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
            else {
                $itemText = '       {0}  {1} {2}' -f $childNum, $childChar, $rowLabel
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Subtext, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
        }

        [Console]::Write($line)
        $row++
    }

    # Blank excess rows from previous render (when collapsing)
    $currentRowCount = $Rows.Count
    if ($PreviousRowCount -gt $currentRowCount) {
        $blankCount = $PreviousRowCount - $currentRowCount
        for ($b = 0; $b -lt $blankCount; $b++) {
            [Console]::SetCursorPosition(0, $row)
            [Console]::Write($emptyLine)
            $row++
        }
    }

    # Empty line
    [Console]::SetCursorPosition(0, $row)
    [Console]::Write($emptyLine)
    $row++

    # Gradient separator line (├──gradient──┤)
    $sepGradient = Get-InTUIGradientLine -Character $hLine -Width $innerWidth
    $sepLine = '  {0}{1}{2}{3}{4}' -f $palette.SurfaceFg, ([char]0x251C), $sepGradient, ([char]0x2524), $reset
    [Console]::SetCursorPosition(0, $row)
    [Console]::Write($sepLine)
    $row++

    # Hint line
    $hintText = '  Arrows | Right/Left: expand | Enter | Esc'
    $hintPadded = (& $fitText $hintText).PadRight($innerWidth)
    $hintLine = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Dim, $hintPadded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
    [Console]::SetCursorPosition(0, $row)
    [Console]::Write($hintLine)
    $row++

    # Bottom border with gradient (╰──gradient──╯)
    $bottomGradient = Get-InTUIGradientLine -Character $hLine -Width $innerWidth
    $bottomLine = '  {0}{1}{2}{3}{4}' -f $palette.SurfaceFg, ([char]0x2570), $bottomGradient, ([char]0x256F), $reset
    [Console]::SetCursorPosition(0, $row)
    [Console]::Write($bottomLine)
    $row++

    # Clear one trailing line to avoid stale artifacts
    try {
        if ($row -lt [Console]::BufferHeight) {
            $windowWidth = [Console]::WindowWidth
            if ($windowWidth -gt 1) {
                [Console]::SetCursorPosition(0, $row)
                [Console]::Write(' ' * ($windowWidth - 1))
            }
        }
    }
    catch { }

    # Move cursor below the box
    [Console]::SetCursorPosition(0, $row)
}
