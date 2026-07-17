function Start-LumenOps {
    <#
    .SYNOPSIS
        Starts the LumenOps glass admin console in your browser.
    .DESCRIPTION
        Launches a local HTTP console backed by PowerShell plugins. Spiritual successor
        to LazyWinAdmin — remoting-native, playbook-driven, and designed for the community.
    .PARAMETER Port
        Local port for the console (default 8787).
    .PARAMETER OpenBrowser
        Open the default browser automatically.
    .PARAMETER Blocking
        Run the HTTP listener in the current process (used by the background server process).
    .EXAMPLE
        Start-LumenOps -OpenBrowser
    .EXAMPLE
        lumen
    #>
    [CmdletBinding()]
    param(
        [int]$Port = 8787,
        [switch]$OpenBrowser,
        [switch]$Blocking
    )

    Initialize-LumenOpsPlugins
    Start-LumenOpsHttpServer -Port $Port -OpenBrowser:$OpenBrowser -Blocking:$Blocking
}

function Stop-LumenOps {
    <#
    .SYNOPSIS
        Stops the running LumenOps console.
    #>
    [CmdletBinding()]
    param()
    Stop-LumenOpsHttpServer
    Write-Host "LumenOps stopped." -ForegroundColor DarkCyan
}

function Get-LumenOpsPlugin {
    <#
    .SYNOPSIS
        Lists discovered LumenOps plugins.
    #>
    [CmdletBinding()]
    param(
        [string]$Id
    )
    Initialize-LumenOpsPlugins
    if ($Id) {
        Get-LumenOpsPluginInternal -Id $Id
    }
    else {
        $script:LumenOpsState.Plugins
    }
}

function Get-LumenOpsAction {
    <#
    .SYNOPSIS
        Lists all command-palette actions across plugins.
    #>
    [CmdletBinding()]
    param()
    Initialize-LumenOpsPlugins
    Get-LumenOpsActionCatalog
}

function Invoke-LumenOpsPlaybook {
    <#
    .SYNOPSIS
        Runs a LumenOps playbook against one or more targets.
    .EXAMPLE
        Invoke-LumenOpsPlaybook -Path ./Playbooks/examples/health-check.json -ComputerName SRV01
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ComputerName = 'localhost',
        [hashtable]$Variables = @{}
    )
    Initialize-LumenOpsPlugins
    Invoke-LumenOpsPlaybookFile -Path $Path -ComputerName $ComputerName -Variables $Variables
}

function Export-LumenOpsInventory {
    <#
    .SYNOPSIS
        Captures a structured inventory snapshot (JSON).
    #>
    [CmdletBinding()]
    param(
        [string]$ComputerName = 'localhost',
        [string]$Path
    )
    Initialize-LumenOpsPlugins
    $result = Invoke-LumenOpsPluginAction -PluginId 'inventory' -ActionId 'snapshot' -ComputerName $ComputerName
    $json = $result | ConvertTo-Json -Depth 10

    if ($Path) {
        $dir = Split-Path -Parent $Path
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Set-Content -Path $Path -Value $json -Encoding UTF8
        Write-Host "Inventory written to $Path" -ForegroundColor Green
    }

    $result
}
