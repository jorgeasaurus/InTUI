#Requires -Modules Pester

<#
.SYNOPSIS
    tmux-based TUI integration tests for InTUI menu components.
.DESCRIPTION
    Launches menu components inside detached tmux sessions, sends keystrokes,
    and asserts on captured screen snapshots. Requires tmux to be installed.
    Skips gracefully if tmux is unavailable.
#>

# Evaluated at discovery time so Pester -Skip works correctly
$script:TmuxAvailable = $null -ne (Get-Command tmux -ErrorAction SilentlyContinue)
$script:DriverDir = Join-Path $PSScriptRoot 'drivers'

BeforeAll {
    $ProjectRoot = Split-Path -Parent $PSScriptRoot
    . "$PSScriptRoot/TUIHarness.ps1"
    $script:DriverDir = Join-Path $PSScriptRoot 'drivers'
}

Describe 'TUI Test Prerequisites' -Skip:(-not $script:TmuxAvailable) {
    It 'tmux is installed' {
        $tmux = Get-Command tmux -ErrorAction SilentlyContinue
        $tmux | Should -Not -BeNullOrEmpty
    }
}

Describe 'Accordion Menu' -Skip:(-not $script:TmuxAvailable) {
    BeforeEach {
        $script:session = New-TUISession `
            -Command ". '$script:DriverDir/accordion.ps1'" `
            -Width 120 -Height 40 -WaitMs 2500
    }
    AfterEach {
        if ($script:session) { Close-TUISession $script:session }
    }

    It 'renders all section titles on initial display' {
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Match 'Endpoint Management'
        $snap | Should -Match 'Policy & Compliance'
        $snap | Should -Match 'Tools'
        $snap | Should -Match 'Quick Action'
    }

    It 'shows child count on collapsed sections' {
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Match 'Endpoint Management \(4\)'
        $snap | Should -Match 'Policy & Compliance \(3\)'
        $snap | Should -Match 'Tools \(3\)'
    }

    It 'renders box chrome elements' {
        $snap = Get-TUISnapshot $script:session
        # Top border corners
        $snap | Should -Match ([regex]::Escape([string][char]0x256D))
        $snap | Should -Match ([regex]::Escape([string][char]0x256E))
        # Bottom border corners
        $snap | Should -Match ([regex]::Escape([string][char]0x2570))
        $snap | Should -Match ([regex]::Escape([string][char]0x256F))
        # Separator
        $snap | Should -Match ([regex]::Escape([string][char]0x251C))
        # Hint line
        $snap | Should -Match 'Arrows.*Right/Left.*expand.*Enter.*Esc'
    }

    It 'shows title and underline' {
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Match 'Test Menu'
    }

    It 'highlights first item with chevron on initial render' {
        $snap = Get-TUISnapshot $script:session
        # The heavy chevron character on the first section line
        $snap | Should -Match ([regex]::Escape([string][char]0x276F))
    }

    It 'expands section on Right arrow showing children' {
        Send-TUIKey $script:session @('Right')
        $snap = Wait-TUIContent $script:session 'Devices'
        $snap | Should -Match '1\.1.*Devices'
        $snap | Should -Match '1\.2.*Apps'
        $snap | Should -Match '1\.3.*Users'
        $snap | Should -Match '1\.4.*Groups'
    }

    It 'shows expanded indicator on parent after Right arrow' {
        Send-TUIKey $script:session @('Right')
        $snap = Wait-TUIContent $script:session 'Devices'
        # Down-pointing triangle for expanded parent
        $snap | Should -Match ([regex]::Escape([string][char]0x25BE) + '.*Endpoint Management')
    }

    It 'collapses section on Left arrow' {
        Send-TUIKey $script:session @('Right')
        $null = Wait-TUIContent $script:session 'Devices'
        Send-TUIKey $script:session @('Left')
        Start-Sleep -Milliseconds 300
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Not -Match '1\.1'
        $snap | Should -Match 'Endpoint Management \(4\)'
    }

    It 'selects child item on Enter and outputs result' {
        Send-TUIKey $script:session @('Right')
        $null = Wait-TUIContent $script:session 'Devices'
        Send-TUIKey $script:session @('Enter')
        $snap = Wait-TUIContent $script:session 'SELECTED:'
        $snap | Should -Match 'SELECTED:Devices'
        $snap | Should -Match 'SECTION:0'
        $snap | Should -Match 'ITEM:0'
    }

    It 'returns CANCELLED on Escape' {
        Send-TUIKey $script:session @('Escape')
        $snap = Wait-TUIContent $script:session 'CANCELLED'
        $snap | Should -Match 'CANCELLED'
    }

    It 'navigates down with wrap-around' {
        # Move past all 4 sections (Down x4 wraps to first)
        Send-TUIKey $script:session @('Down', 'Down', 'Down', 'Down')
        Start-Sleep -Milliseconds 300
        $snap = Get-TUISnapshot $script:session
        # After wrapping, chevron should be back on first section
        # The snap should show the chevron on Endpoint Management line
        $snap | Should -Match ([regex]::Escape([string][char]0x276F) + '.*1.*Endpoint Management')
    }

    It 'shows direct-action indicator for IsDirect sections' {
        $snap = Get-TUISnapshot $script:session
        # Right arrow character for direct-action section
        $snap | Should -Match ([regex]::Escape([string][char]0x2192) + '.*Quick Action')
    }

    It 'returns immediately on Enter for IsDirect section' {
        # Navigate to Quick Action (section 4, index 3)
        Send-TUIKey $script:session @('Down', 'Down', 'Down')
        Start-Sleep -Milliseconds 300
        Send-TUIKey $script:session @('Enter')
        $snap = Wait-TUIContent $script:session 'SELECTED:'
        $snap | Should -Match 'SELECTED:Quick Action'
        $snap | Should -Match 'ITEM:-1'
    }

    It 'expands second section and shows correct child numbering' {
        Send-TUIKey $script:session @('Down', 'Right')
        $snap = Wait-TUIContent $script:session '2\.1'
        $snap | Should -Match '2\.1.*Config Profiles'
        $snap | Should -Match '2\.2.*Compliance'
        $snap | Should -Match '2\.3.*Conditional Access'
    }
}

Describe 'Single-Select Menu' -Skip:(-not $script:TmuxAvailable) {
    BeforeEach {
        $script:session = New-TUISession `
            -Command ". '$script:DriverDir/single-select.ps1'" `
            -Width 120 -Height 40 -WaitMs 2500
    }
    AfterEach {
        if ($script:session) { Close-TUISession $script:session }
    }

    It 'renders all choices with numbers and chevrons' {
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Match '1.*Devices'
        $snap | Should -Match '2.*Apps'
        $snap | Should -Match '9.*Back'
        # Right-pointing triangle chevron
        $snap | Should -Match ([regex]::Escape([string][char]0x25B8))
    }

    It 'shows title in the box' {
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Match 'Select an option'
    }

    It 'shows hint line with back option' {
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Match 'Esc to go back'
    }

    It 'selects item on Enter and returns index' {
        Send-TUIKey $script:session @('Down', 'Down', 'Enter')
        $snap = Wait-TUIContent $script:session 'INDEX:'
        $snap | Should -Match 'INDEX:2'
        $snap | Should -Match 'CHOICE:Users'
    }

    It 'returns BACK on Escape' {
        Send-TUIKey $script:session @('Escape')
        $snap = Wait-TUIContent $script:session 'BACK'
        $snap | Should -Match 'BACK'
    }

    It 'wraps from first to last on Up' {
        Send-TUIKey $script:session @('Up')
        Start-Sleep -Milliseconds 300
        $snap = Get-TUISnapshot $script:session
        # Chevron should be on the last item (Back, item 9)
        $snap | Should -Match ([regex]::Escape([string][char]0x276F) + '.*9.*Back')
    }

    It 'wraps from last to first on Down' {
        # Go to last item, then one more Down
        for ($i = 0; $i -lt 9; $i++) { Send-TUIKey $script:session @('Down') -DelayMs 100 }
        Start-Sleep -Milliseconds 300
        $snap = Get-TUISnapshot $script:session
        # Should be back on first item
        $snap | Should -Match ([regex]::Escape([string][char]0x276F) + '.*1.*Devices')
    }
}

Describe 'Multi-Select Menu' -Skip:(-not $script:TmuxAvailable) {
    BeforeEach {
        $script:session = New-TUISession `
            -Command ". '$script:DriverDir/multi-select.ps1'" `
            -Width 120 -Height 40 -WaitMs 2500
    }
    AfterEach {
        if ($script:session) { Close-TUISession $script:session }
    }

    It 'renders checkboxes on all items' {
        $snap = Get-TUISnapshot $script:session
        # Unchecked box character
        $snap | Should -Match ([regex]::Escape([string][char]0x2610))
    }

    It 'shows multi-select hints' {
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Match 'Space to toggle'
        $snap | Should -Match 'Enter to confirm'
    }

    It 'toggles checkbox on Space' {
        Send-TUIKey $script:session @('Space')
        Start-Sleep -Milliseconds 300
        $snap = Get-TUISnapshot $script:session
        # Checked box character should appear
        $snap | Should -Match ([regex]::Escape([string][char]0x2611))
    }

    It 'selects multiple and returns them on Enter' {
        Send-TUIKey $script:session @('Space', 'Down', 'Down', 'Space', 'Enter')
        $snap = Wait-TUIContent $script:session 'SELECTED:'
        $snap | Should -Match 'SELECTED:Windows'
        $snap | Should -Match 'SELECTED:iOS'
    }

    It 'returns NONE on Escape' {
        Send-TUIKey $script:session @('Escape')
        $snap = Wait-TUIContent $script:session 'NONE'
        $snap | Should -Match 'NONE'
    }

    It 'toggles all with A key' {
        Send-TUIKey $script:session @('A')
        Start-Sleep -Milliseconds 300
        Send-TUIKey $script:session @('Enter')
        $snap = Wait-TUIContent $script:session 'SELECTED:'
        $snap | Should -Match 'SELECTED:Windows'
        $snap | Should -Match 'SELECTED:macOS'
        $snap | Should -Match 'SELECTED:iOS'
        $snap | Should -Match 'SELECTED:Android'
        $snap | Should -Match 'SELECTED:Linux'
    }
}

Describe 'Viewport Scrolling' -Skip:(-not $script:TmuxAvailable) {
    BeforeEach {
        # Use a short terminal (20 rows) to force viewport scrolling for 30 items
        $script:session = New-TUISession `
            -Command ". '$script:DriverDir/viewport.ps1'" `
            -Width 120 -Height 20 -WaitMs 2500
    }
    AfterEach {
        if ($script:session) { Close-TUISession $script:session }
    }

    It 'shows scroll-down indicator when items exceed viewport' {
        $snap = Get-TUISnapshot $script:session
        # Down-pointing triangle with "more below"
        $snap | Should -Match 'more below'
    }

    It 'shows scroll-up indicator after scrolling down' {
        # Scroll down enough to trigger the "more above" indicator
        for ($i = 0; $i -lt 20; $i++) {
            Send-TUIKey $script:session @('Down') -DelayMs 50
        }
        Start-Sleep -Milliseconds 500
        $snap = Get-TUISnapshot $script:session
        $snap | Should -Match 'more above'
    }

    It 'can select an item beyond initial viewport' {
        # Navigate to item 15 and select
        for ($i = 0; $i -lt 14; $i++) {
            Send-TUIKey $script:session @('Down') -DelayMs 50
        }
        Send-TUIKey $script:session @('Enter')
        $snap = Wait-TUIContent $script:session 'INDEX:'
        $snap | Should -Match 'INDEX:14'
        $snap | Should -Match 'CHOICE:Item 15'
    }
}
