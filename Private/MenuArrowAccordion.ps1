function Build-InTUIAccordionRows {
    <#
    .SYNOPSIS
        Builds a flat list of visible rows from accordion section definitions.
    .DESCRIPTION
        Computes the visible parent and child rows based on which section (if any)
        is currently expanded. Returns an array of hashtables with Type, Label,
        SectionIndex, ChildIndex, ChildCount, Expanded, and IsDirect fields.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)]
        [object[]]$Sections,

        [Parameter()]
        [int]$ExpandedIndex = -1
    )

    $rows = [System.Collections.ArrayList]::new()

    for ($s = 0; $s -lt $Sections.Count; $s++) {
        $section = $Sections[$s]
        # Support both 'Items' (InTUI convention) and 'Children' (TB convention)
        $children = if ($section.Children) { $section.Children } elseif ($section.Items) { $section.Items } else { @() }
        $isDirect = [bool]$section.IsDirect
        $isExpanded = ($s -eq $ExpandedIndex) -and ($children.Count -gt 0)

        $null = $rows.Add(@{
            Type         = 'parent'
            SectionIndex = $s
            Label        = $section.Title
            ChildCount   = $children.Count
            Expanded     = $isExpanded
            IsDirect     = $isDirect
        })

        if ($isExpanded) {
            for ($c = 0; $c -lt $children.Count; $c++) {
                $null = $rows.Add(@{
                    Type         = 'child'
                    SectionIndex = $s
                    ChildIndex   = $c
                    Label        = $children[$c]
                })
            }
        }
    }

    return @(, $rows.ToArray())
}

function Show-InTUIMenuArrowAccordion {
    <#
    .SYNOPSIS
        Accordion-style main menu. Left/Right expand/collapse, single-expansion
        constraint. Returns selection hashtable or $null on Escape.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [array]$Sections,

        [Parameter()]
        [int]$PageSize = 20
    )

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
    $titleUnderline = ('  ' + ([string]$hLine * $plainTitle.Length)).PadRight($innerWidth)
    Write-Host ('  {0}{1}{2}{3}{4}{5}' -f $palette.SurfaceFg, $border, $palette.Dim, $titleUnderline, $reset, ('{0}{1}{2}' -f $palette.SurfaceFg, $border, $reset))

    # Record anchor position
    $anchorTop = [Console]::CursorTop

    $expandedIndex = -1
    $selectedIndex = 0
    $previousRowCount = 0

    $rows = Build-InTUIAccordionRows -Sections $Sections -ExpandedIndex $expandedIndex

    try {
        try { [Console]::CursorVisible = $false } catch { }

        # Initial render
        Render-InTUIAccordionBox -Rows $rows -SelectedIndex $selectedIndex -AnchorTop $anchorTop -PreviousRowCount $previousRowCount
        $previousRowCount = $rows.Count

        while ($true) {
            $key = [Console]::ReadKey($true)
            $itemCount = $rows.Count

            switch ($key.Key) {
                'UpArrow' {
                    if ($selectedIndex -gt 0) {
                        $selectedIndex--
                    }
                    else {
                        $selectedIndex = $itemCount - 1
                    }
                    Render-InTUIAccordionBox -Rows $rows -SelectedIndex $selectedIndex -AnchorTop $anchorTop -PreviousRowCount $previousRowCount
                    $previousRowCount = $rows.Count
                }
                'DownArrow' {
                    if ($selectedIndex -lt ($itemCount - 1)) {
                        $selectedIndex++
                    }
                    else {
                        $selectedIndex = 0
                    }
                    Render-InTUIAccordionBox -Rows $rows -SelectedIndex $selectedIndex -AnchorTop $anchorTop -PreviousRowCount $previousRowCount
                    $previousRowCount = $rows.Count
                }
                'RightArrow' {
                    $currentRow = $rows[$selectedIndex]
                    if ($currentRow.Type -eq 'parent' -and -not $currentRow.Expanded -and -not $currentRow.IsDirect -and $currentRow.ChildCount -gt 0) {
                        $expandedIndex = $currentRow.SectionIndex
                        $rows = Build-InTUIAccordionRows -Sections $Sections -ExpandedIndex $expandedIndex

                        # Move selection to first child
                        for ($f = 0; $f -lt $rows.Count; $f++) {
                            if ($rows[$f].Type -eq 'child' -and $rows[$f].SectionIndex -eq $expandedIndex) {
                                $selectedIndex = $f
                                break
                            }
                        }

                        Render-InTUIAccordionBox -Rows $rows -SelectedIndex $selectedIndex -AnchorTop $anchorTop -PreviousRowCount $previousRowCount
                        $previousRowCount = $rows.Count
                    }
                }
                'LeftArrow' {
                    if ($expandedIndex -ge 0) {
                        $collapseTarget = $expandedIndex
                        $expandedIndex = -1
                        $rows = Build-InTUIAccordionRows -Sections $Sections -ExpandedIndex $expandedIndex

                        # Move selection to the collapsed parent
                        $selectedIndex = $collapseTarget
                        if ($selectedIndex -ge $rows.Count) {
                            $selectedIndex = $rows.Count - 1
                        }

                        Render-InTUIAccordionBox -Rows $rows -SelectedIndex $selectedIndex -AnchorTop $anchorTop -PreviousRowCount $previousRowCount
                        $previousRowCount = $rows.Count
                    }
                }
                'Enter' {
                    $currentRow = $rows[$selectedIndex]

                    if ($currentRow.Type -eq 'child') {
                        # Resolve the child text from the section data
                        $section = $Sections[$currentRow.SectionIndex]
                        $children = if ($section.Children) { $section.Children } elseif ($section.Items) { $section.Items } else { @() }
                        return @{
                            SectionIndex = $currentRow.SectionIndex
                            ItemIndex    = $currentRow.ChildIndex
                            ItemText     = $children[$currentRow.ChildIndex]
                        }
                    }
                    elseif ($currentRow.IsDirect) {
                        # Direct-action parent: return immediately
                        return @{
                            SectionIndex = $currentRow.SectionIndex
                            ItemIndex    = -1
                            ItemText     = $currentRow.Label
                        }
                    }
                    else {
                        # Toggle expand/collapse on parent
                        if ($currentRow.Expanded) {
                            $expandedIndex = -1
                        }
                        else {
                            $expandedIndex = $currentRow.SectionIndex
                        }
                        $rows = Build-InTUIAccordionRows -Sections $Sections -ExpandedIndex $expandedIndex

                        # If expanding, move to first child; if collapsing, stay on parent
                        if ($expandedIndex -ge 0 -and $currentRow.ChildCount -gt 0) {
                            for ($f = 0; $f -lt $rows.Count; $f++) {
                                if ($rows[$f].Type -eq 'child' -and $rows[$f].SectionIndex -eq $expandedIndex) {
                                    $selectedIndex = $f
                                    break
                                }
                            }
                        }
                        else {
                            for ($f = 0; $f -lt $rows.Count; $f++) {
                                if ($rows[$f].Type -eq 'parent' -and $rows[$f].SectionIndex -eq $currentRow.SectionIndex) {
                                    $selectedIndex = $f
                                    break
                                }
                            }
                        }

                        Render-InTUIAccordionBox -Rows $rows -SelectedIndex $selectedIndex -AnchorTop $anchorTop -PreviousRowCount $previousRowCount
                        $previousRowCount = $rows.Count
                    }
                }
                'Escape' {
                    return $null
                }
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $true } catch { }
    }
}
