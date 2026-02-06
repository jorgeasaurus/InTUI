@{
    RootModule        = 'InTUI.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'InTUI'
    Description       = 'Intune TUI - A Spectre Console based terminal UI for Microsoft Intune management via Graph API'
    PowerShellVersion = '7.2'
    RequiredModules   = @(
        'Microsoft.Graph.Authentication',
        'PwshSpectreConsole'
    )
    FunctionsToExport = @(
        'Start-InTUI',
        'Connect-InTUI',
        'Export-InTUIData'
    )
    PrivateData       = @{
        PSData = @{
            Tags       = @('Intune', 'Graph', 'TUI', 'Spectre', 'Console')
            ProjectUri = 'https://github.com/jorgeasaurus/InTUI'
        }
    }
}
