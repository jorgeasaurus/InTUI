function Render-InTUIBarChart {
    <#
    .SYNOPSIS
        Renders horizontal bar chart with block characters.
        Replaces Format-SpectreBarChart / New-SpectreChartItem.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [array]$Items,   # Array of @{ Label = ''; Value = 0; Color = 'green' }

        [Parameter()]
        [int]$MaxBarWidth = 40
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    $colorMap = @{
        'blue'   = $palette.Blue
        'green'  = $palette.Green
        'red'    = $palette.Red
        'yellow' = $palette.Yellow
        'cyan'   = $palette.Cyan
        'grey'   = $palette.Grey
        'orange' = $palette.Peach
        'mauve'  = $palette.Mauve
        'teal'   = $palette.Teal
        'white'  = $palette.White
    }

    # Title
    $ansiTitle = ConvertFrom-InTUIMarkup -Text $Title
    Write-Host ""
    Write-Host "  $($palette.Bold)$ansiTitle$reset"
    Write-Host ""

    if (-not $Items -or $Items.Count -eq 0) { return }

    # Find max value and max label length
    $maxValue = ($Items | ForEach-Object { $_.Value } | Measure-Object -Maximum).Maximum
    if ($maxValue -le 0) { $maxValue = 1 }
    $maxLabelLen = ($Items | ForEach-Object { Measure-InTUIDisplayWidth -Text $_.Label } | Measure-Object -Maximum).Maximum

    $blockFull = [char]0x2588

    foreach ($item in $Items) {
        $label = $item.Label
        $value = $item.Value
        $color = if ($item.Color) { $item.Color.ToLower() } else { 'blue' }
        $ansiColor = if ($colorMap.ContainsKey($color)) { $colorMap[$color] } else { $palette.Blue }

        $labelPad = [Math]::Max(0, $maxLabelLen - (Measure-InTUIDisplayWidth -Text $label))
        $barLen = if ($maxValue -gt 0) { [int]([Math]::Ceiling(($value / $maxValue) * $MaxBarWidth)) } else { 0 }
        $barLen = [Math]::Max(0, $barLen)

        $bar = [string]::new($blockFull, $barLen)
        Write-Host "  $($palette.Text)$label$(' ' * $labelPad)$reset $ansiColor$bar$reset $($palette.Dim)$value$reset"
    }
    Write-Host ""
}
