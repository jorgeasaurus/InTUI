function Render-InTUIMenuBox {
    <#
    .SYNOPSIS
        Renders menu items inside a rounded-corner box with in-place redraw.
    .DESCRIPTION
        Draws menu items with numbered indicators and chevrons inside a Unicode
        box. Uses Console.SetCursorPosition + Console.Write for flicker-free
        in-place updates. Supports single-select and multi-select modes with
        viewport scrolling for long lists.

        The caller renders the top border and title area before the loop; this
        function renders: empty line, items, empty line, gradient separator,
        hint line, and bottom border.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string[]]$Items,

        [Parameter(Mandatory)]
        [int]$SelectedIndex,

        [Parameter(Mandatory)]
        [int]$AnchorTop,

        [Parameter()]
        [bool[]]$Checked,

        [Parameter()]
        [switch]$IncludeBack,

        [Parameter()]
        [switch]$IncludeQuit,

        [Parameter()]
        [switch]$MultiSelect,

        [Parameter()]
        [int]$ViewportOffset = 0,

        [Parameter()]
        [int]$ViewportSize = 0
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    $innerWidth = Get-InTUIConsoleInnerWidth
    $border = [char]0x2502
    $hLine = [char]0x2500

    $fitText = {
        param([string]$Text)
        if ($null -eq $Text) { return '' }
        if ($Text.Length -le $innerWidth) { return $Text }
        if ($innerWidth -le 3) { return $Text.Substring(0, $innerWidth) }
        return $Text.Substring(0, $innerWidth - 3) + '...'
    }

    $bufferHeight = [Console]::BufferHeight

    # Determine viewport boundaries
    $useViewport = ($ViewportSize -gt 0) -and ($ViewportSize -lt $Items.Count)
    if ($useViewport) {
        $showAbove = ($ViewportOffset -gt 0)
        $showBelow = (($ViewportOffset + $ViewportSize) -lt $Items.Count)
        $slotCount = $ViewportSize
    }
    else {
        $showAbove = $false
        $showBelow = $false
        $slotCount = $Items.Count
    }

    $row = $AnchorTop

    # Empty line inside box
    $emptyLine = '  {0}{1}{2}{3}{4}' -f $palette.SurfaceFg, $border, (' ' * $innerWidth), $border, $reset
    if ($row -lt $bufferHeight) {
        [Console]::SetCursorPosition(0, $row)
        [Console]::Write($emptyLine)
    }
    $row++

    # Render item slots
    for ($slot = 0; $slot -lt $slotCount; $slot++) {
        if ($row -ge $bufferHeight) { break }
        [Console]::SetCursorPosition(0, $row)

        # Scroll-up indicator in the first slot
        if ($useViewport -and $slot -eq 0 -and $showAbove) {
            $aboveCount = $ViewportOffset
            $indicatorText = '     {0} {1} more above' -f ([char]0x25B4), $aboveCount
            $indicatorPadded = (& $fitText $indicatorText).PadRight($innerWidth)
            $line = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Dim, $indicatorPadded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            [Console]::Write($line)
            $row++
            continue
        }

        # Scroll-down indicator in the last slot
        if ($useViewport -and $slot -eq ($slotCount - 1) -and $showBelow) {
            $belowCount = $Items.Count - ($ViewportOffset + $ViewportSize)
            $indicatorText = '     {0} {1} more below' -f ([char]0x25BE), $belowCount
            $indicatorPadded = (& $fitText $indicatorText).PadRight($innerWidth)
            $line = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Dim, $indicatorPadded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            [Console]::Write($line)
            $row++
            continue
        }

        # Map slot to actual item index
        $i = if ($useViewport) { $ViewportOffset + $slot } else { $slot }

        $num = $i + 1
        $isHighlighted = ($i -eq $SelectedIndex)
        # Strip any [color]...[/] markup -- the renderer controls item colors
        $label = Strip-InTUIMarkup -Text $Items[$i]

        if ($MultiSelect -and $Checked) {
            if ($Checked[$i]) {
                $checkChar = [char]0x2611  # checked box
            }
            else {
                $checkChar = [char]0x2610  # unchecked box
            }

            if ($isHighlighted) {
                $chevron = [char]0x276F
                $itemText = '  {0} {1} {2}  {3} {4}' -f $chevron, $checkChar, $num, ([char]0x25B8), $label
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}{6}{7}' -f $palette.SurfaceFg, $border, $palette.BgSelect, $palette.Mauve, $palette.Bold, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
            else {
                $checkColor = if ($Checked[$i]) { $palette.Green } else { $palette.Dim }
                $itemText = '     {0} {1}  {2} {3}' -f $checkChar, $num, ([char]0x25B8), $label
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $checkColor, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
        }
        else {
            if ($isHighlighted) {
                $chevron = [char]0x276F
                $itemText = '  {0} {1}  {2} {3}' -f $chevron, $num, ([char]0x25B8), $label
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}{6}{7}' -f $palette.SurfaceFg, $border, $palette.BgSelect, $palette.Mauve, $palette.Bold, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
            else {
                $itemText = '     {0}  {1} {2}' -f $num, ([char]0x25B8), $label
                $padded = (& $fitText $itemText).PadRight($innerWidth)
                $line = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Text, $padded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
            }
        }

        [Console]::Write($line)
        $row++
    }

    # Empty line
    if ($row -lt $bufferHeight) {
        [Console]::SetCursorPosition(0, $row)
        [Console]::Write($emptyLine)
    }
    $row++

    # Gradient separator line (├──gradient──┤)
    if ($row -lt $bufferHeight) {
        $sepGradient = Get-InTUIGradientLine -Character $hLine -Width $innerWidth
        $sepLine = '  {0}{1}{2}{3}{4}' -f $palette.SurfaceFg, ([char]0x251C), $sepGradient, ([char]0x2524), $reset
        [Console]::SetCursorPosition(0, $row)
        [Console]::Write($sepLine)
    }
    $row++

    # Hint line inside the box
    if ($MultiSelect) {
        $hintText = '  Space to toggle, A for all, Enter to confirm'
    }
    else {
        $hintText = '  Use arrow keys to navigate, Enter to select'
    }

    if ($IncludeBack) {
        $hintText += ', Esc to go back'
    }
    elseif ($IncludeQuit) {
        $hintText += ', Esc to quit'
    }

    if ($row -lt $bufferHeight) {
        $hintPadded = $hintText.PadRight($innerWidth)
        $hintLine = '  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Dim, $hintPadded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset)
        [Console]::SetCursorPosition(0, $row)
        [Console]::Write($hintLine)
    }
    $row++

    # Bottom border with gradient (╰──gradient──╯)
    if ($row -lt $bufferHeight) {
        $bottomGradient = Get-InTUIGradientLine -Character $hLine -Width $innerWidth
        $bottomLine = '  {0}{1}{2}{3}{4}' -f $palette.SurfaceFg, ([char]0x2570), $bottomGradient, ([char]0x256F), $reset
        [Console]::SetCursorPosition(0, $row)
        [Console]::Write($bottomLine)
    }
    $row++

    # Move cursor below the box
    if ($row -lt $bufferHeight) {
        [Console]::SetCursorPosition(0, $row)
    }
}
