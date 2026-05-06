function Split-InTUIPlainTextByDisplayWidth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text,

        [Parameter(Mandatory)]
        [int]$Width
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return @('')
    }

    if ($Width -le 0) {
        return @($Text)
    }

    $segments = [System.Collections.Generic.List[string]]::new()
    $remaining = $Text

    while ((Measure-InTUIDisplayWidth -Text $remaining) -gt $Width) {
        $cutLength = 0
        $lineWidth = 0

        for ($index = 0; $index -lt $remaining.Length; $index++) {
            $charWidth = Measure-InTUIDisplayWidth -Text ([string]$remaining[$index])
            if (($lineWidth + $charWidth) -gt $Width) {
                break
            }

            $lineWidth += $charWidth
            $cutLength++
        }

        if ($cutLength -le 0) {
            $cutLength = 1
        }

        $candidate = $remaining.Substring(0, $cutLength).TrimEnd()
        if ($cutLength -lt $remaining.Length -and $remaining[$cutLength] -eq ' ') {
            $segments.Add($candidate)
            $remaining = $remaining.Substring($cutLength + 1).TrimStart()
        }
        elseif ($candidate.LastIndexOf(' ') -gt 0) {
            $breakIndex = $candidate.LastIndexOf(' ')
            $segments.Add($candidate.Substring(0, $breakIndex).TrimEnd())
            $remaining = $remaining.Substring($breakIndex + 1).TrimStart()
        }
        else {
            $segments.Add($candidate)
            $remaining = $remaining.Substring($cutLength)
        }
    }

    $segments.Add($remaining)
    return $segments.ToArray()
}

function Split-InTUIPanelContentLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line,

        [Parameter(Mandatory)]
        [int]$Width
    )

    $plainText = Strip-InTUIMarkup -Text $Line
    $plainWidth = Measure-InTUIDisplayWidth -Text $plainText

    if ($plainWidth -le $Width) {
        return @([pscustomobject]@{
                Text         = ConvertFrom-InTUIMarkup -Text $Line
                DisplayWidth = $plainWidth
            })
    }

    $style = $null
    $textToWrap = $plainText
    if ($Line -match '^\[(?<Style>[^\]]+)\](?<Text>.*)\[/\]$') {
        $style = $Matches.Style
        $textToWrap = $Matches.Text
    }

    $wrappedLines = [System.Collections.Generic.List[object]]::new()
    foreach ($wrappedText in (Split-InTUIPlainTextByDisplayWidth -Text $textToWrap -Width $Width)) {
        $displayText = $wrappedText
        if ($null -ne $style) {
            $displayText = ConvertFrom-InTUIMarkup -Text "[$style]$wrappedText[/]"
        }

        $wrappedLines.Add([pscustomobject]@{
                Text         = $displayText
                DisplayWidth = Measure-InTUIDisplayWidth -Text $wrappedText
            })
    }

    return $wrappedLines.ToArray()
}

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
        foreach ($wrappedLine in (Split-InTUIPanelContentLine -Line $line -Width $contentWidth)) {
            $padRight = [Math]::Max(0, $contentWidth - $wrappedLine.DisplayWidth)
            Write-Host "$indent$borderAnsi$vertical$reset $($wrappedLine.Text)$reset$(' ' * $padRight) $borderAnsi$vertical$reset"
        }
    }

    # Bottom border
    Write-Host "$indent$borderAnsi$bottomLeft$([string]::new($horizontal, ($boxWidth - 2)))$bottomRight$reset"
}
