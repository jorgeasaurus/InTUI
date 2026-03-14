function Read-InTUITextInput {
    <#
    .SYNOPSIS
        Styled text input prompt with default value support.
        Replaces Read-SpectreText.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [string]$DefaultAnswer = ''
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    $ansiMessage = ConvertFrom-InTUIMarkup -Text $Message
    $defaultHint = if ($DefaultAnswer) { " $($palette.Dim)($DefaultAnswer)$reset" } else { '' }

    Write-Host "$ansiMessage$defaultHint`: " -NoNewline
    $input = Read-Host

    if ([string]::IsNullOrWhiteSpace($input) -and $DefaultAnswer) {
        return $DefaultAnswer
    }

    return $input
}

function Read-InTUIConfirmInput {
    <#
    .SYNOPSIS
        Y/N confirmation prompt. Replaces Read-SpectreConfirm.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [bool]$DefaultAnswer = $false
    )

    $palette = Get-InTUIColorPalette
    $reset = $palette.Reset

    $ansiMessage = ConvertFrom-InTUIMarkup -Text $Message
    $hint = if ($DefaultAnswer) { '[Y/n]' } else { '[y/N]' }

    Write-Host "$ansiMessage $($palette.Dim)$hint$reset " -NoNewline
    $input = Read-Host

    if ([string]::IsNullOrWhiteSpace($input)) {
        return $DefaultAnswer
    }

    return ($input.Trim().ToLower() -eq 'y')
}
