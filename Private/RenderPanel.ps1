function Render-InTUIPanel {
    <#
    .SYNOPSIS
        Renders content inside a Unicode box with gradient top/bottom borders.
        Replaces Format-SpectrePanel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Content,

        [Parameter()]
        [string]$Title = '',

        [Parameter()]
        [string]$BorderColor = 'Blue'
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset
    $innerWidth = Get-InTUIConsoleInnerWidth

    # Map border color name to palette
    $borderAnsi = switch ($BorderColor.ToLower()) {
        'blue'   { $palette.Blue }
        'green'  { $palette.Green }
        'red'    { $palette.Red }
        'yellow' { $palette.Yellow }
        'cyan'   { $palette.Cyan }
        'cyan1'  { $palette.Cyan }
        'grey'   { $palette.Grey }
        'mauve'  { $palette.Mauve }
        default  { $palette.Blue }
    }

    # Box characters
    $topLeft     = [char]0x256D
    $topRight    = [char]0x256E
    $bottomLeft  = [char]0x2570
    $bottomRight = [char]0x256F
    $horizontal  = [char]0x2500
    $vertical    = [char]0x2502

    # Match accordion box layout: 2-space indent + border + innerWidth + border = WindowWidth
    $boxWidth = $innerWidth + 2
    $contentWidth = $boxWidth - 4  # 2 border + 2 padding
    $indent = '  '

    # Top border with optional title
    if ($Title) {
        $plainTitle = Strip-InTUIMarkup -Text $Title
        $ansiTitle = ConvertFrom-InTUIMarkup -Text $Title
        $titleDisplayWidth = Measure-InTUIDisplayWidth -Text $plainTitle
        $lineLen = $boxWidth - 4 - $titleDisplayWidth
        $leftLine = [Math]::Max(1, [int]([Math]::Floor($lineLen / 2)))
        $rightLine = [Math]::Max(1, $lineLen - $leftLine)
        Write-Host "$indent$borderAnsi$topLeft$([string]::new($horizontal, $leftLine))$reset $ansiTitle $borderAnsi$([string]::new($horizontal, $rightLine))$topRight$reset"
    }
    else {
        Write-Host "$indent$borderAnsi$topLeft$([string]::new($horizontal, ($boxWidth - 2)))$topRight$reset"
    }

    # Content lines
    $lines = $Content -split "`n"
    foreach ($line in $lines) {
        $line = $line.TrimEnd("`r")
        $plainLine = Strip-InTUIMarkup -Text $line
        $ansiLine = ConvertFrom-InTUIMarkup -Text $line
        $displayWidth = Measure-InTUIDisplayWidth -Text $plainLine

        # Truncate based on visual display width
        if ($displayWidth -gt $contentWidth) {
            # Walk the plain text to find the cut point at the right visual column
            $cutLen = 0
            $cutWidth = 0
            for ($ci = 0; $ci -lt $plainLine.Length; $ci++) {
                $charWidth = Measure-InTUIDisplayWidth -Text ([string]$plainLine[$ci])
                if (($cutWidth + $charWidth) -gt ($contentWidth - 3)) { break }
                $cutWidth += $charWidth
                $cutLen++
            }
            $plainLine = $plainLine.Substring(0, $cutLen) + '...'
            $ansiLine = $plainLine
            $displayWidth = $cutWidth + 3
        }
        $padRight = [Math]::Max(0, $contentWidth - $displayWidth)
        Write-Host "$indent$borderAnsi$vertical$reset $ansiLine$reset$(' ' * $padRight) $borderAnsi$vertical$reset"
    }

    # Bottom border
    Write-Host "$indent$borderAnsi$bottomLeft$([string]::new($horizontal, ($boxWidth - 2)))$bottomRight$reset"
}
