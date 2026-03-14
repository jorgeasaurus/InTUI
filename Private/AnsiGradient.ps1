function Get-InTUIGradientString {
    <#
    .SYNOPSIS
        Per-character RGB interpolation for gradient text.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Text,

        [Parameter()]
        [int[]]$StartRGB = @(166, 227, 161),   # Green primary

        [Parameter()]
        [int[]]$EndRGB = @(137, 180, 250)       # Blue accent
    )

    $palette = Get-InTUIColorPalette
    if (-not $palette.Reset) { return $Text }

    $e = [char]0x1B
    $len = $Text.Length
    if ($len -le 1) {
        return "$e[38;2;$($StartRGB[0]);$($StartRGB[1]);$($StartRGB[2])m$Text$($palette.Reset)"
    }

    $sb = [System.Text.StringBuilder]::new($len * 20)
    for ($i = 0; $i -lt $len; $i++) {
        $t = $i / ($len - 1)
        $r = [int]($StartRGB[0] + ($EndRGB[0] - $StartRGB[0]) * $t)
        $g = [int]($StartRGB[1] + ($EndRGB[1] - $StartRGB[1]) * $t)
        $b = [int]($StartRGB[2] + ($EndRGB[2] - $StartRGB[2]) * $t)
        $null = $sb.Append("$e[38;2;${r};${g};${b}m$($Text[$i])")
    }
    $null = $sb.Append($palette.Reset)
    return $sb.ToString()
}

function Get-InTUIGradientLine {
    <#
    .SYNOPSIS
        Repeated character with gradient color. Used for box borders.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [char]$Character = ([char]0x2500),   # horizontal line

        [Parameter()]
        [int]$Width = 60,

        [Parameter()]
        [int[]]$StartRGB = @(166, 227, 161),

        [Parameter()]
        [int[]]$EndRGB = @(137, 180, 250)
    )

    $text = [string]::new($Character, $Width)
    return Get-InTUIGradientString -Text $text -StartRGB $StartRGB -EndRGB $EndRGB
}
