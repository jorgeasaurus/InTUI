function Show-InTUIMenuArrowMulti {
    <#
    .SYNOPSIS
        Arrow-key multi-selection menu. Space toggles, A toggles all, Enter confirms.
        Returns array of selected indices.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string[]]$Choices,

        [Parameter()]
        [switch]$IncludeBack,

        [Parameter()]
        [int]$PageSize = 15
    )

    if ($Choices.Count -eq 0) { return @() }

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    $innerWidth = Get-InTUIConsoleInnerWidth
    $border = [char]0x2502
    $hLine = [char]0x2500

    # Render top border with gradient (once, before the loop)
    $topGradient = Get-InTUIGradientLine -Character $hLine -Width $innerWidth
    Write-Host ('  {0}{1}{2}{3}{4}' -f $palette.SurfaceFg, ([char]0x256D), $topGradient, ([char]0x256E), $reset)

    # Render title inside the box
    $plainTitle = Strip-InTUIMarkup -Text $Title
    $titlePadded = ('  {0}' -f $plainTitle).PadRight($innerWidth)
    Write-Host ('  {0}{1}{2}{3}{4}{5}{6}' -f $palette.SurfaceFg, $border, $palette.Teal, $palette.Bold, $titlePadded, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset))

    # Title underline
    $titleUnderline = ('  {0}' -f ([string]([char]0x2500) * $plainTitle.Length)).PadRight($innerWidth)
    Write-Host ('  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Dim, $titleUnderline, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset))

    # Record anchor position
    $anchorTop = [Console]::CursorTop

    $selectedIndex = 0
    $itemCount = $Choices.Count
    $checked = [bool[]]::new($itemCount)

    # Viewport sizing (chrome = empty + empty + separator + hint + bottom-border + cursor-below)
    $chromeRows = 6

    # Ensure buffer has room for items + chrome before computing viewport
    $anchorTop = Ensure-InTUIBufferSpace -AnchorTop $anchorTop -NeededRows ([math]::Min($itemCount, $PageSize) + $chromeRows)

    $maxVisible = [Math]::Max(3, [Console]::WindowHeight - $anchorTop - $chromeRows)
    $viewportSize = if ($itemCount -gt $maxVisible) { $maxVisible } else { 0 }
    $viewportOffset = 0

    $adjustViewport = {
        if ($viewportSize -le 0) { return }
        $hasAbove = ($viewportOffset -gt 0)
        $hasBelow = (($viewportOffset + $viewportSize) -lt $itemCount)
        $visibleFirst = $viewportOffset + $(if ($hasAbove) { 1 } else { 0 })
        $visibleLast  = $viewportOffset + $viewportSize - 1 - $(if ($hasBelow) { 1 } else { 0 })
        $newOffset = $viewportOffset
        if ($selectedIndex -lt $visibleFirst) {
            $newOffset = [Math]::Max(0, $selectedIndex - 1)
            if ($selectedIndex -eq 0) { $newOffset = 0 }
        }
        elseif ($selectedIndex -gt $visibleLast) {
            $newOffset = [Math]::Min($itemCount - $viewportSize, $selectedIndex - $viewportSize + 2)
            if ($selectedIndex -eq ($itemCount - 1)) { $newOffset = $itemCount - $viewportSize }
        }
        Set-Variable -Name viewportOffset -Value $newOffset -Scope 1
    }

    try {
        try { [Console]::CursorVisible = $false } catch { }

        # Initial render
        & $adjustViewport
        Render-InTUIMenuBox -Items $Choices -SelectedIndex $selectedIndex -AnchorTop $anchorTop `
            -Checked $checked -MultiSelect -IncludeBack:$IncludeBack `
            -ViewportOffset $viewportOffset -ViewportSize $viewportSize

        while ($true) {
            $key = [Console]::ReadKey($true)

            switch ($key.Key) {
                'UpArrow' {
                    if ($selectedIndex -gt 0) {
                        $selectedIndex--
                    }
                    else {
                        $selectedIndex = $itemCount - 1
                    }
                }
                'DownArrow' {
                    if ($selectedIndex -lt ($itemCount - 1)) {
                        $selectedIndex++
                    }
                    else {
                        $selectedIndex = 0
                    }
                }
                'Spacebar' {
                    $checked[$selectedIndex] = -not $checked[$selectedIndex]
                }
                'A' {
                    $allChecked = ($checked | Where-Object { $_ }).Count -eq $itemCount
                    for ($i = 0; $i -lt $itemCount; $i++) {
                        $checked[$i] = -not $allChecked
                    }
                }
                'Enter' {
                    $result = @()
                    for ($i = 0; $i -lt $itemCount; $i++) {
                        if ($checked[$i]) { $result += $i }
                    }
                    return $result
                }
                'Escape' {
                    return @()
                }
            }

            & $adjustViewport
            Render-InTUIMenuBox -Items $Choices -SelectedIndex $selectedIndex -AnchorTop $anchorTop `
                -Checked $checked -MultiSelect -IncludeBack:$IncludeBack `
                -ViewportOffset $viewportOffset -ViewportSize $viewportSize
        }
    }
    finally {
        try { [Console]::CursorVisible = $true } catch { }
    }
}
