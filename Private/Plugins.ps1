function Initialize-LumenOpsPlugins {
    $script:LumenOpsState.Plugins.Clear()
    $pluginRoot = Join-Path $script:LumenOpsRoot 'Plugins'
    if (-not (Test-Path $pluginRoot)) { return }

    foreach ($dir in Get-ChildItem -Path $pluginRoot -Directory) {
        $manifestPath = Join-Path $dir.FullName 'plugin.json'
        $scriptPath = Join-Path $dir.FullName 'plugin.ps1'
        if (-not (Test-Path $manifestPath) -or -not (Test-Path $scriptPath)) { continue }

        try {
            $manifest = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json

            $plugin = [pscustomobject]@{
                Id          = [string]$manifest.id
                Name        = [string]$manifest.name
                Description = [string]$manifest.description
                Icon        = [string]$manifest.icon
                Category    = [string]$manifest.category
                Version     = [string]$manifest.version
                Actions     = @($manifest.actions)
                Path        = $dir.FullName
            }

            $script:LumenOpsState.Plugins.Add($plugin)
        }
        catch {
            Write-Warning "Failed to load plugin '$($dir.Name)': $($_.Exception.Message)"
        }
    }
}

function Get-LumenOpsPluginInternal {
    param([string]$Id)
    $script:LumenOpsState.Plugins | Where-Object { $_.Id -eq $Id } | Select-Object -First 1
}

function Invoke-LumenOpsPluginAction {
    param(
        [Parameter(Mandatory)][string]$PluginId,
        [Parameter(Mandatory)][string]$ActionId,
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{}
    )

    $plugin = Get-LumenOpsPluginInternal -Id $PluginId
    if (-not $plugin) { throw "Unknown plugin: $PluginId" }

    $action = $plugin.Actions | Where-Object { $_.id -eq $ActionId } | Select-Object -First 1
    if (-not $action) { throw "Unknown action '$ActionId' on plugin '$PluginId'" }

    $safePlugin = ($PluginId -replace '[^a-zA-Z0-9_]', '_')
    $safeAction = ($ActionId -replace '[^a-zA-Z0-9_]', '_')
    $fnName = "Invoke-LumenPlugin_${safePlugin}_${safeAction}"
    $cmd = Get-Command -Name $fnName -CommandType Function -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $alt = "Invoke-LumenPlugin_$safePlugin"
        $cmd = Get-Command -Name $alt -CommandType Function -ErrorAction SilentlyContinue
        if ($cmd) { $fnName = $alt }
    }
    if (-not $cmd) {
        $available = @(Get-Command -Name 'Invoke-LumenPlugin_*' -CommandType Function -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
        throw "Plugin function not found for $PluginId/$ActionId (looked for $fnName). Loaded: $($available -join ', ')"
    }

    Write-LumenOpsLog -Level Action -Target $ComputerName -Action "$PluginId.$ActionId" -Message "Running $($plugin.Name) → $($action.name)"

    $result = & $cmd -ComputerName $ComputerName -Parameters $Parameters -ActionId $ActionId
    Write-LumenOpsLog -Level Success -Target $ComputerName -Action "$PluginId.$ActionId" -Message "Completed $($action.name)"

    return [pscustomobject]@{
        Plugin    = $PluginId
        Action    = $ActionId
        Target    = $ComputerName
        Timestamp = (Get-Date).ToString('o')
        Data      = $result
    }
}

function Get-LumenOpsActionCatalog {
    $actions = foreach ($plugin in $script:LumenOpsState.Plugins) {
        foreach ($action in $plugin.Actions) {
            $actionIcon = $plugin.Icon
            if ($action.PSObject.Properties.Name -contains 'icon' -and $action.icon) {
                $actionIcon = [string]$action.icon
            }

            $keywords = @()
            if ($action.PSObject.Properties.Name -contains 'keywords' -and $action.keywords) {
                $keywords = @($action.keywords)
            }

            $confirm = $false
            if ($action.PSObject.Properties.Name -contains 'confirm') {
                $confirm = [bool]$action.confirm
            }

            $destructive = $false
            if ($action.PSObject.Properties.Name -contains 'destructive') {
                $destructive = [bool]$action.destructive
            }

            $description = ''
            if ($action.PSObject.Properties.Name -contains 'description' -and $action.description) {
                $description = [string]$action.description
            }

            [pscustomobject]@{
                Id          = "$($plugin.Id).$($action.id)"
                PluginId    = $plugin.Id
                ActionId    = [string]$action.id
                Name        = [string]$action.name
                Description = $description
                Category    = $plugin.Category
                Icon        = $actionIcon
                Confirm     = $confirm
                Destructive = $destructive
                Keywords    = $keywords
            }
        }
    }
    $actions | Sort-Object Category, Name
}
