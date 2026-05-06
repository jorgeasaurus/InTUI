@{
    RootModule        = 'InTUI.psm1'
    ModuleVersion     = '1.0.1'
    GUID              = 'bec8fb22-9b4e-4ae9-900c-6d7aac7ec498'
    Author            = 'jorgeasaurus'
    CompanyName       = 'Unknown'
    Copyright         = '(c) jorgeasaurus. All rights reserved.'
    Description       = 'Intune TUI - A terminal UI for Microsoft Intune management via Graph API'
    PowerShellVersion = '7.2'
    RequiredModules   = @(
        'Microsoft.Graph.Authentication'
    )
    FunctionsToExport = @(
        'Start-InTUI',
        'Connect-InTUI',
        'Export-InTUIData'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport   = @('intui')
    PrivateData       = @{
        PSData = @{
            Tags         = @('Intune', 'Graph', 'TUI', 'Terminal', 'ANSI', 'Microsoft', 'Endpoint', 'Management')
            LicenseUri   = 'https://github.com/jorgeasaurus/InTUI/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/jorgeasaurus/InTUI'
            ReleaseNotes = @'
1.0.1
- Fixed TUI layout repainting so dashboard and Global Search status rows no longer push the logo out of view.
- Added compact header rendering for dense shell screens and cleared transient loading spinner rows before repainting.
- Improved panels to wrap long content by display width instead of truncating with ellipses.
- Hardened ANSI markup stripping for nested and leftover style tags in labels.
- Added Intune report response helpers and mobile app intent-state parsing helpers.
- Reworked app install status views to use supported Intune report and mobileAppIntentAndStates data paths.
- Preserved existing mobile app assignments when adding single or bulk assignments, avoiding accidental assignment replacement and duplicates.
- Expanded device configuration and What's Applied views to include Settings Catalog, ADMX, device configuration, and intent policy report data.
- Added Intune Device ID to device hardware details and switched device rename to the supported setDeviceName action.
- Improved compliance policy filtering by using client-side search/platform filtering where Graph filtering is unreliable.
- Improved group search/list queries, including Microsoft Graph search syntax and safer ordering behavior.
- Bounded sign-in log queries to a recent window with smaller pages for faster Conditional Access log loading.
- Reduced Autopilot device list payloads and surfaced Graph errors from Autopilot list calls.
- Improved BitLocker recovery key handling, including permission-specific warnings and support for nested recovery key responses.
- Added regression coverage for report conversion, app intent parsing, app assignments, query builders, panel wrapping, dashboard/search layout, and multi-select behavior.
'@
        }
    }
}
