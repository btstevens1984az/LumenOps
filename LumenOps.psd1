@{
    RootModule           = 'LumenOps.psm1'
    ModuleVersion        = '1.0.0'
    GUID                 = 'a7c3e91f-4b2d-4e8a-9f1c-6d5e8b0a2c4d'
    Author               = 'Brandon Stevens'
    CompanyName          = 'btstevens1984az'
    Copyright            = '(c) 2026 Brandon Stevens. MIT License.'
    Description          = 'LumenOps — a modern, remoting-native PowerShell admin console. Spiritual successor to LazyWinAdmin with a glass UI, command palette, playbooks, and a community plugin system.'
    PowerShellVersion    = '7.0'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport    = @(
        'Start-LumenOps',
        'Stop-LumenOps',
        'Get-LumenOpsPlugin',
        'Invoke-LumenOpsPlaybook',
        'Get-LumenOpsAction',
        'Export-LumenOpsInventory'
    )
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('lumen', 'lumenops')
    PrivateData          = @{
        PSData = @{
            Tags         = @('Admin', 'Windows', 'GUI', 'Remoting', 'WMI', 'CIM', 'SysAdmin', 'LazyWinAdmin', 'Dashboard', 'Playbooks')
            LicenseUri   = 'https://github.com/btstevens1984az/LumenOps/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/btstevens1984az/LumenOps'
            ReleaseNotes = 'Initial release — glass UI, plugins, playbooks, fleet pulse, command palette.'
        }
    }
}
