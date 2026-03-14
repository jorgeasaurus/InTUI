function Get-InTUIConsoleInnerWidth {
    <#
    .SYNOPSIS
        Returns usable inner width for content rendering, minimum 48.
    #>
    [CmdletBinding()]
    param()

    $width = 80
    try {
        $width = [Console]::WindowWidth - 4
    }
    catch {
        $width = 80
    }

    return [Math]::Max(48, $width)
}

function Measure-InTUIDisplayWidth {
    <#
    .SYNOPSIS
        Returns the visual column width of a string, accounting for characters
        that render as 2 columns in terminal emulators (East Asian Wide,
        Fullwidth, and common ambiguous-width symbols).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) { return 0 }

    $width = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $cp = [int]$Text[$i]

        # Handle surrogate pairs (emoji, CJK Extension B+)
        if ($cp -ge 0xD800 -and $cp -le 0xDBFF -and ($i + 1) -lt $Text.Length) {
            $low = [int]$Text[$i + 1]
            if ($low -ge 0xDC00 -and $low -le 0xDFFF) {
                $cp = 0x10000 + (($cp - 0xD800) -shl 10) + ($low - 0xDC00)
                $i++
            }
        }

        # Control characters and ANSI escape components: 0 width
        if ($cp -lt 0x20 -or ($cp -ge 0x7F -and $cp -lt 0xA0)) {
            continue
        }

        # 2-column ranges
        if (
            # East Asian Wide / Fullwidth
            ($cp -ge 0x1100 -and $cp -le 0x115F) -or   # Hangul Jamo
            ($cp -ge 0x2E80 -and $cp -le 0x303E) -or   # CJK Radicals, Ideographic, Symbols
            ($cp -ge 0x3041 -and $cp -le 0x33BF) -or   # Hiragana, Katakana, Bopomofo, CJK Compat
            ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or   # CJK Unified Ext A
            ($cp -ge 0x4E00 -and $cp -le 0x9FFF) -or   # CJK Unified Ideographs
            ($cp -ge 0xAC00 -and $cp -le 0xD7AF) -or   # Hangul Syllables
            ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or   # CJK Compatibility Ideographs
            ($cp -ge 0xFE30 -and $cp -le 0xFE6F) -or   # CJK Compatibility Forms
            ($cp -ge 0xFF01 -and $cp -le 0xFF60) -or   # Fullwidth Forms
            ($cp -ge 0xFFE0 -and $cp -le 0xFFE6) -or   # Fullwidth Signs
            ($cp -ge 0x20000 -and $cp -le 0x2FFFF) -or # CJK Extension B+
            ($cp -ge 0x30000 -and $cp -le 0x3FFFF) -or # CJK Extension G+
            # Supplemental emoji (actual pictographic emoji)
            ($cp -ge 0x1F000 -and $cp -le 0x1FAFF)     # Emoji & Symbols
        ) {
            $width += 2
        }
        else {
            $width += 1
        }
    }

    return $width
}
