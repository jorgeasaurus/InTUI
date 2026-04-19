# Catppuccin theme definitions (RGB triplets)
# Reference: https://catppuccin.com/palette
$script:CatppuccinThemes = @{
    Mocha = @{
        Text      = @(205, 214, 244)   # #CDD6F4
        Subtext   = @(166, 173, 200)   # #A6ADC8
        Dim       = @(127, 132, 156)   # #7F849C
        Blue      = @(166, 227, 161)   # #A6E3A1 (green primary in this app)
        Green     = @(166, 227, 161)   # #A6E3A1
        Red       = @(243, 139, 168)   # #F38BA8
        Yellow    = @(249, 226, 175)   # #F9E2AF
        Mauve     = @(137, 180, 250)   # #89B4FA (blue accent)
        Teal      = @(148, 226, 213)   # #94E2D5
        Peach     = @(250, 179, 135)   # #FAB387
        Cyan      = @(137, 220, 235)   # #89DCEB
        Orange    = @(250, 179, 135)   # #FAB387
        White     = @(205, 214, 244)   # #CDD6F4
        Grey      = @(127, 132, 156)   # #7F849C
        Surface   = @(49, 50, 68)      # #313244
        SurfaceFg = @(69, 71, 90)      # #45475A
        BgSelect  = @(69, 71, 90)      # #45475A
    }
    Macchiato = @{
        Text      = @(202, 211, 245)   # #CAD3F5
        Subtext   = @(165, 173, 206)   # #A5ADCE
        Dim       = @(128, 135, 162)   # #8087A2
        Blue      = @(166, 218, 149)   # #A6DA95
        Green     = @(166, 218, 149)   # #A6DA95
        Red       = @(237, 135, 150)   # #ED8796
        Yellow    = @(238, 212, 159)   # #EED49F
        Mauve     = @(138, 173, 244)   # #8AADF4
        Teal      = @(139, 213, 202)   # #8BD5CA
        Peach     = @(245, 169, 127)   # #F5A97F
        Cyan      = @(145, 215, 227)   # #91D7E3
        Orange    = @(245, 169, 127)   # #F5A97F
        White     = @(202, 211, 245)   # #CAD3F5
        Grey      = @(128, 135, 162)   # #8087A2
        Surface   = @(54, 58, 79)      # #363A4F
        SurfaceFg = @(73, 77, 100)     # #494D64
        BgSelect  = @(73, 77, 100)     # #494D64
    }
    Frappe = @{
        Text      = @(198, 208, 245)   # #C6D0F5
        Subtext   = @(165, 173, 206)   # #A5ADCE
        Dim       = @(131, 139, 167)   # #838BA7
        Blue      = @(166, 209, 137)   # #A6D189
        Green     = @(166, 209, 137)   # #A6D189
        Red       = @(231, 130, 132)   # #E78284
        Yellow    = @(229, 200, 144)   # #E5C890
        Mauve     = @(140, 170, 238)   # #8CAAEE
        Teal      = @(129, 200, 190)   # #81C8BE
        Peach     = @(239, 159, 118)   # #EF9F76
        Cyan      = @(153, 209, 219)   # #99D1DB
        Orange    = @(239, 159, 118)   # #EF9F76
        White     = @(198, 208, 245)   # #C6D0F5
        Grey      = @(131, 139, 167)   # #838BA7
        Surface   = @(65, 69, 89)      # #414559
        SurfaceFg = @(81, 87, 109)     # #51576D
        BgSelect  = @(81, 87, 109)     # #51576D
    }
    Latte = @{
        Text      = @(76, 79, 105)     # #4C4F69
        Subtext   = @(92, 95, 119)     # #5C5F77
        Dim       = @(124, 127, 147)   # #7C7F93
        Blue      = @(64, 160, 43)     # #40A02B
        Green     = @(64, 160, 43)     # #40A02B
        Red       = @(210, 15, 57)     # #D20F39
        Yellow    = @(223, 142, 29)    # #DF8E1D
        Mauve     = @(30, 102, 245)    # #1E66F5
        Teal      = @(23, 146, 153)    # #179299
        Peach     = @(254, 100, 11)    # #FE640B
        Cyan      = @(4, 165, 229)     # #04A5E5
        Orange    = @(254, 100, 11)    # #FE640B
        White     = @(76, 79, 105)     # #4C4F69
        Grey      = @(124, 127, 147)   # #7C7F93
        Surface   = @(204, 208, 218)   # #CCD0DA
        SurfaceFg = @(172, 176, 190)   # #ACB0BE
        BgSelect  = @(172, 176, 190)   # #ACB0BE
    }
}

function Get-InTUIColorPalette {
    <#
    .SYNOPSIS
        Returns the active Catppuccin theme palette as ANSI 24-bit escape strings.
    #>
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        # Graceful degradation: return empty strings on older PS
        $empty = @{}
        foreach ($key in @('Text','Subtext','Dim','Blue','Green','Red','Yellow','Mauve',
                           'Teal','Peach','Surface','SurfaceFg','BgSelect','Cyan','Orange','White',
                           'Grey','Bold','Italic','DimStyle','Reset')) {
            $empty[$key] = ''
        }
        return $empty
    }

    $themeName = if ($script:InTUIConfig -and $script:InTUIConfig.Theme) {
        $script:InTUIConfig.Theme
    } else {
        'Mocha'
    }

    $theme = $script:CatppuccinThemes[$themeName]
    if (-not $theme) { $theme = $script:CatppuccinThemes['Mocha'] }

    $e = [char]0x1B
    $palette = @{
        Bold     = "$e[1m"
        Italic   = "$e[3m"
        DimStyle = "$e[2m"
        Reset    = "$e[0m"
    }

    foreach ($key in @('Text','Subtext','Dim','Blue','Green','Red','Yellow','Mauve',
                       'Teal','Peach','Cyan','Orange','White','Grey')) {
        $rgb = $theme[$key]
        $palette[$key] = "$e[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"
    }

    # Background colors
    $rgb = $theme['Surface']
    $palette['Surface'] = "$e[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"

    $rgb = $theme['SurfaceFg']
    $palette['SurfaceFg'] = "$e[38;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"

    $rgb = $theme['BgSelect']
    $palette['BgSelect'] = "$e[48;2;$($rgb[0]);$($rgb[1]);$($rgb[2])m"

    return $palette
}

function ConvertFrom-InTUIMarkup {
    <#
    .SYNOPSIS
        Converts [color]text[/] Spectre-style markup to ANSI escape codes.
    .DESCRIPTION
        Stack-based parser that handles nested tags correctly. Supports: blue, green,
        red, yellow, cyan, grey, white, bold, dim, DeepSkyBlue1, DarkOrange, orange1,
        Cyan1, steelblue1_1, compound tags like [bold white], [white bold], [grey dim].
        [/] pops the current style and restores the parent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    $palette = Get-InTUIColorPalette
    if (-not $palette.Reset) {
        return Strip-InTUIMarkup -Text $Text
    }

    $reset = $palette.Reset

    $colorMap = @{
        'blue'           = $palette.Blue
        'green'          = $palette.Green
        'red'            = $palette.Red
        'yellow'         = $palette.Yellow
        'cyan'           = $palette.Cyan
        'cyan1'          = $palette.Cyan
        'grey'           = $palette.Grey
        'gray'           = $palette.Grey
        'white'          = $palette.White
        'bold'           = $palette.Bold
        'dim'            = $palette.DimStyle
        'italic'         = $palette.Italic
        'deepskyblue1'   = $palette.Blue
        'darkorange'     = $palette.Peach
        'orange1'        = $palette.Peach
        'steelblue1_1'   = $palette.Blue
        'orange'         = $palette.Peach
        'mauve'          = $palette.Mauve
        'teal'           = $palette.Teal
        'peach'          = $palette.Peach
    }

    $styleStack = [System.Collections.Generic.Stack[string]]::new()
    $buf = [System.Text.StringBuilder]::new($Text.Length * 2)
    $len = $Text.Length
    $pos = 0

    while ($pos -lt $len) {
        $ch = $Text[$pos]

        # Escaped [[ → literal [
        if ($ch -eq '[' -and ($pos + 1) -lt $len -and $Text[$pos + 1] -eq '[') {
            $buf.Append('[') | Out-Null
            $pos += 2
            continue
        }

        # Tag or close marker
        if ($ch -eq '[') {
            $close = $Text.IndexOf(']', $pos + 1)
            if ($close -eq -1) {
                $buf.Append($ch) | Out-Null
                $pos++
                continue
            }

            $tag = $Text.Substring($pos + 1, $close - $pos - 1)

            if ($tag -eq '/') {
                # Pop style, emit reset, re-apply parent if any
                if ($styleStack.Count -gt 0) { $styleStack.Pop() | Out-Null }
                $buf.Append($reset) | Out-Null
                if ($styleStack.Count -gt 0) { $buf.Append($styleStack.Peek()) | Out-Null }
            }
            else {
                $parts = $tag.Trim() -split '\s+'
                $ansi = ''
                foreach ($part in $parts) {
                    $key = $part.ToLower()
                    if ($colorMap.ContainsKey($key)) { $ansi += $colorMap[$key] }
                }
                if ($ansi) {
                    $styleStack.Push($ansi) | Out-Null
                    $buf.Append($ansi) | Out-Null
                }
            }

            $pos = $close + 1
            continue
        }

        # Escaped ]] → literal ]
        if ($ch -eq ']' -and ($pos + 1) -lt $len -and $Text[$pos + 1] -eq ']') {
            $buf.Append(']') | Out-Null
            $pos += 2
            continue
        }

        $buf.Append($ch) | Out-Null
        $pos++
    }

    if ($styleStack.Count -gt 0) { $buf.Append($reset) | Out-Null }

    return $buf.ToString()
}

function Strip-InTUIMarkup {
    <#
    .SYNOPSIS
        Removes all [color]...[/] markup tags, returning plain text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return $Text }

    # Handle escaped brackets
    $result = $Text -replace '\[\[', "`0LBRACKET`0"
    $result = $result -replace '\]\]', "`0RBRACKET`0"

    # Remove [tag]...[/] keeping inner content - innermost first, loop until stable
    do {
        $prev = $result
        $result = [regex]::Replace($result, '\[([^\]\/]+)\]([^\[]*?)\[/\]', '$2')
    } while ($result -ne $prev)

    # Restore escaped brackets
    $result = $result -replace "`0LBRACKET`0", '['
    $result = $result -replace "`0RBRACKET`0", ']'

    return $result
}

function Write-InTUIText {
    <#
    .SYNOPSIS
        Converts markup to ANSI and writes to host. Replaces Write-SpectreHost.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [AllowEmptyString()]
        [string]$Text = '',

        [Parameter()]
        [switch]$NoNewline
    )

    $converted = ConvertFrom-InTUIMarkup -Text $Text
    if ($NoNewline) {
        Write-Host $converted -NoNewline
    }
    else {
        Write-Host $converted
    }
}
