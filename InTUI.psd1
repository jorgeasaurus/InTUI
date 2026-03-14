@{
    RootModule        = 'InTUI.psm1'
    ModuleVersion     = '1.0.0'
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
            ReleaseNotes = 'Initial release with custom ANSI TUI engine.'
        }
    }
}
