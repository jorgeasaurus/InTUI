function Show-InTUIMenuClassic {
    <#
    .SYNOPSIS
        Numbered input fallback for non-interactive hosts.
        Supports single and multi-select.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [string[]]$Choices,

        [Parameter()]
        [switch]$MultiSelect
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    Write-Host ""
    Write-InTUIText $Title
    Write-Host ""

    for ($i = 0; $i -lt $Choices.Count; $i++) {
        $num = $i + 1
        $item = ConvertFrom-InTUIMarkup -Text $Choices[$i]
        Write-Host "  $($palette.Blue)[$num]$reset $item"
    }

    Write-Host ""

    if ($MultiSelect) {
        Write-Host "$($palette.Dim)Enter numbers separated by commas (e.g., 1,3,5), or 'a' for all:$reset" -NoNewline
        $userInput = Read-Host
        if ($userInput -eq 'a') {
            return @(0..($Choices.Count - 1))
        }
        $indices = @()
        foreach ($part in ($userInput -split ',')) {
            $trimmed = $part.Trim()
            $num = 0
            if ([int]::TryParse($trimmed, [ref]$num) -and $num -ge 1 -and $num -le $Choices.Count) {
                $indices += ($num - 1)
            }
        }
        return $indices
    }
    else {
        Write-Host "$($palette.Dim)Enter number (or 0 to go back):$reset " -NoNewline
        $userInput = Read-Host
        $num = 0
        if ([int]::TryParse($userInput, [ref]$num)) {
            if ($num -eq 0) { return 'Back' }
            if ($num -ge 1 -and $num -le $Choices.Count) { return ($num - 1) }
        }
        return 'Back'
    }
}
