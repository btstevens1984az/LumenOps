#Requires -Version 7.0
<#
.SYNOPSIS
    LumenOps — modern PowerShell admin console.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LumenOpsRoot = $PSScriptRoot
$script:LumenOpsState = [ordered]@{
    Server       = $null
    Listener     = $null
    Runspace     = $null
    Port         = 8787
    StartedAt    = $null
    Targets      = [hashtable]::Synchronized(@{})
    ActionLog    = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    Plugins      = [System.Collections.Generic.List[object]]::new()
    Cancellation = $null
}

# Dot-source private helpers
foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue) {
    . $file.FullName
}

# Dot-source public commands
foreach ($file in Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue) {
    . $file.FullName
}

# Load plugin scripts into module/script scope (must not be inside a function)
$pluginRoot = Join-Path $script:LumenOpsRoot 'Plugins'
if (Test-Path $pluginRoot) {
    foreach ($dir in Get-ChildItem -Path $pluginRoot -Directory) {
        $pluginScript = Join-Path $dir.FullName 'plugin.ps1'
        if (Test-Path $pluginScript) {
            . $pluginScript
        }
    }
}

Initialize-LumenOpsPlugins

Set-Alias -Name lumen -Value Start-LumenOps -Scope Global -Force -ErrorAction SilentlyContinue
Set-Alias -Name lumenops -Value Start-LumenOps -Scope Global -Force -ErrorAction SilentlyContinue

Export-ModuleMember -Function @(
    'Start-LumenOps',
    'Stop-LumenOps',
    'Get-LumenOpsPlugin',
    'Invoke-LumenOpsPlaybook',
    'Get-LumenOpsAction',
    'Export-LumenOpsInventory'
) -Alias @('lumen', 'lumenops')
