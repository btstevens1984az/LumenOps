function Start-LumenOpsHttpServer {
    param(
        [int]$Port = 8787,
        [switch]$OpenBrowser,
        [switch]$Blocking
    )

    if ($script:LumenOpsState.Listener) {
        throw "LumenOps is already running on port $($script:LumenOpsState.Port). Use Stop-LumenOps first."
    }

    if (-not $Blocking) {
        try {
            $null = Invoke-WebRequest -Uri "http://127.0.0.1:$Port/api/health" -UseBasicParsing -TimeoutSec 1
            throw "LumenOps appears to already be listening on port $Port. Use Stop-LumenOps first."
        }
        catch [System.Net.Http.HttpRequestException] { }
        catch {
            if ($_.Exception.Message -match 'already be listening') { throw }
        }
    }

    # Non-blocking mode: spawn a dedicated pwsh process (avoids runspace/Import-Module deadlocks)
    if (-not $Blocking) {
        $moduleManifest = Join-Path $script:LumenOpsRoot 'LumenOps.psd1'
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue)?.Source
        if (-not $pwsh) { $pwsh = (Get-Command powershell -ErrorAction SilentlyContinue)?.Source }
        if (-not $pwsh) { throw 'PowerShell executable not found (pwsh/powershell).' }

        $stateDir = Join-Path ([IO.Path]::GetTempPath()) 'LumenOps'
        if (-not (Test-Path $stateDir)) { New-Item -ItemType Directory -Path $stateDir -Force | Out-Null }
        $pidFile = Join-Path $stateDir "server-$Port.pid"

        $argList = @(
            '-NoProfile'
            '-ExecutionPolicy', 'Bypass'
            '-Command'
            "Import-Module '$moduleManifest' -Force; Start-LumenOps -Port $Port -Blocking"
        )

        $proc = Start-Process -FilePath $pwsh -ArgumentList $argList -PassThru
        $proc.Id | Set-Content -Path $pidFile -Encoding ascii
        $script:LumenOpsState.Port = $Port
        $script:LumenOpsState.StartedAt = Get-Date
        $script:LumenOpsState.ServerProcessId = $proc.Id
        $script:LumenOpsState.PidFile = $pidFile

        $url = "http://127.0.0.1:$Port/"
        $ready = $false
        foreach ($i in 1..40) {
            Start-Sleep -Milliseconds 250
            try {
                $null = Invoke-WebRequest -Uri "${url}api/health" -UseBasicParsing -TimeoutSec 1
                $ready = $true
                break
            }
            catch { }
        }

        Write-Host ""
        Write-Host "  ╔══════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "  ║           L U M E N O P S                ║" -ForegroundColor Cyan
        Write-Host "  ║     Modern PowerShell Admin Console      ║" -ForegroundColor DarkCyan
        Write-Host "  ╚══════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Console:  $url" -ForegroundColor Green
        Write-Host "  PID:      $($proc.Id)$(if (-not $ready) { ' (still starting…)' })" -ForegroundColor DarkGray
        Write-Host "  Stop:     Stop-LumenOps" -ForegroundColor DarkGray
        Write-Host ""

        if ($OpenBrowser) { Start-Process $url }

        return [pscustomobject]@{
            Url       = $url
            Port      = $Port
            StartedAt = $script:LumenOpsState.StartedAt
            Plugins   = $script:LumenOpsState.Plugins.Count
            ProcessId = $proc.Id
            Ready     = $ready
        }
    }

    # Blocking mode — used by the dedicated server process
    $listener = [System.Net.HttpListener]::new()
    $prefix = "http://127.0.0.1:$Port/"
    $listener.Prefixes.Add($prefix)

    try {
        $listener.Start()
    }
    catch {
        throw "Unable to bind $prefix — is the port in use? $($_.Exception.Message)"
    }

    $script:LumenOpsState.Listener = $listener
    $script:LumenOpsState.Port = $Port
    $script:LumenOpsState.StartedAt = Get-Date

    Write-LumenOpsLog -Level Success -Message "LumenOps console listening at $prefix"

    if ($OpenBrowser) {
        Start-Process "http://127.0.0.1:$Port/"
    }

    Write-Host "LumenOps listening on $prefix (blocking). Ctrl+C to stop." -ForegroundColor DarkCyan

    try {
        while ($listener.IsListening) {
            try {
                $context = $listener.GetContext()
                try {
                    Invoke-LumenOpsHttpRequest -Context $context
                }
                catch {
                    try {
                        Write-LumenOpsResponse -Response $context.Response -StatusCode 500 -Body @{
                            error = $_.Exception.Message
                        }
                    }
                    catch { }
                }
            }
            catch {
                break
            }
        }
    }
    finally {
        try { $listener.Stop() } catch { }
        try { $listener.Close() } catch { }
        $script:LumenOpsState.Listener = $null
    }
}

function Stop-LumenOpsHttpServer {
    $port = if ($script:LumenOpsState.Port) { $script:LumenOpsState.Port } else { 8787 }
    $stateDir = Join-Path ([IO.Path]::GetTempPath()) 'LumenOps'
    $pidFile = Join-Path $stateDir "server-$port.pid"

    $pids = @()
    if ($script:LumenOpsState.ServerProcessId) { $pids += [int]$script:LumenOpsState.ServerProcessId }
    if (Test-Path $pidFile) {
        $fromFile = Get-Content $pidFile -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($fromFile) { $pids += [int]$fromFile }
    }

    foreach ($processId in ($pids | Select-Object -Unique)) {
        try {
            $p = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($p) {
                Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
            }
        }
        catch { }
    }

    if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }

    if ($script:LumenOpsState.Listener) {
        try { $script:LumenOpsState.Listener.Stop() } catch { }
        try { $script:LumenOpsState.Listener.Close() } catch { }
    }

    if ($script:LumenOpsState.Server) {
        try { $script:LumenOpsState.Server.Stop() } catch { }
        try { $script:LumenOpsState.Server.Dispose() } catch { }
    }

    if ($script:LumenOpsState.Runspace) {
        try { $script:LumenOpsState.Runspace.Close() } catch { }
        try { $script:LumenOpsState.Runspace.Dispose() } catch { }
    }

    $script:LumenOpsState.Listener = $null
    $script:LumenOpsState.Server = $null
    $script:LumenOpsState.Runspace = $null
    $script:LumenOpsState.ServerProcessId = $null
    Write-LumenOpsLog -Level Info -Message 'LumenOps console stopped.'
}

function Invoke-LumenOpsHttpRequest {
    param([System.Net.HttpListenerContext]$Context)

    $request = $Context.Request
    $response = $Context.Response
    $path = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath.TrimEnd('/'))
    if ([string]::IsNullOrEmpty($path)) { $path = '/' }

    if ($request.HttpMethod -eq 'OPTIONS') {
        Write-LumenOpsResponse -Response $response -StatusCode 204 -Body $null
        return
    }

    if ($path -like '/api/*') {
        Invoke-LumenOpsApi -Request $request -Response $response -Path $path
        return
    }

    $uiRoot = Get-LumenOpsUiRoot
    $relative = if ($path -eq '/' ) { 'index.html' } else { $path.TrimStart('/') }
    $filePath = Join-Path $uiRoot $relative

    $fullUi = [System.IO.Path]::GetFullPath($uiRoot)
    $fullFile = [System.IO.Path]::GetFullPath($filePath)
    if (-not $fullFile.StartsWith($fullUi)) {
        Write-LumenOpsResponse -Response $response -StatusCode 403 -Body @{ error = 'Forbidden' }
        return
    }

    if (-not (Test-Path $fullFile)) {
        $fullFile = Join-Path $uiRoot 'index.html'
    }

    $bytes = [System.IO.File]::ReadAllBytes($fullFile)
    $ext = [System.IO.Path]::GetExtension($fullFile)
    Write-LumenOpsResponse -Response $response -ContentType (Get-LumenOpsContentType $ext) -Body $bytes
}

function Invoke-LumenOpsApi {
    param(
        [System.Net.HttpListenerRequest]$Request,
        [System.Net.HttpListenerResponse]$Response,
        [string]$Path
    )

    try {
        switch -Regex ($Path) {
            '^/api/health$' {
                Write-LumenOpsResponse -Response $Response -Body @{
                    status    = 'ok'
                    version   = '1.0.0'
                    startedAt = $script:LumenOpsState.StartedAt
                    platform  = if (Test-LumenOpsIsWindows) { 'windows' } else { 'cross-platform' }
                    hostname  = [System.Net.Dns]::GetHostName()
                    plugins   = $script:LumenOpsState.Plugins.Count
                    psVersion = $PSVersionTable.PSVersion.ToString()
                }
            }
            '^/api/plugins$' {
                Write-LumenOpsResponse -Response $Response -Body @{
                    plugins = @($script:LumenOpsState.Plugins | ForEach-Object {
                        [pscustomobject]@{
                            id          = $_.Id
                            name        = $_.Name
                            description = $_.Description
                            icon        = $_.Icon
                            category    = $_.Category
                            version     = $_.Version
                            actions     = $_.Actions
                        }
                    })
                }
            }
            '^/api/actions$' {
                Write-LumenOpsResponse -Response $Response -Body @{
                    actions = @(Get-LumenOpsActionCatalog)
                }
            }
            '^/api/logs$' {
                $logs = @($script:LumenOpsState.ActionLog)
                Write-LumenOpsResponse -Response $Response -Body @{
                    logs = @($logs | Sort-Object Timestamp -Descending | Select-Object -First 100)
                }
            }
            '^/api/playbooks$' {
                if ($Request.HttpMethod -eq 'GET') {
                    Write-LumenOpsResponse -Response $Response -Body @{
                        playbooks = @(Get-LumenOpsPlaybooks)
                    }
                }
                elseif ($Request.HttpMethod -eq 'POST') {
                    $body = Read-LumenOpsRequestBody -Request $Request
                    $path = Get-LumenOpsBodyValue $body 'path'
                    $target = Get-LumenOpsBodyValue $body 'computerName' 'localhost'
                    $result = Invoke-LumenOpsPlaybookFile -Path $path -ComputerName $target
                    Write-LumenOpsResponse -Response $Response -Body $result
                }
            }
            '^/api/fleet/pulse$' {
                $body = Read-LumenOpsRequestBody -Request $Request
                $hosts = @(Get-LumenOpsBodyValue $body 'hosts' @())
                if ($hosts.Count -eq 0) { $hosts = @('localhost') }
                $pulse = foreach ($h in $hosts) {
                    Get-LumenOpsHostPulse -ComputerName $h
                }
                Write-LumenOpsResponse -Response $Response -Body @{ pulse = @($pulse) }
            }
            '^/api/targets$' {
                if ($Request.HttpMethod -eq 'GET') {
                    $targets = @($script:LumenOpsState.Targets.Keys | ForEach-Object {
                        [pscustomobject]@{ name = $_; meta = $script:LumenOpsState.Targets[$_] }
                    })
                    Write-LumenOpsResponse -Response $Response -Body @{ targets = $targets }
                }
                elseif ($Request.HttpMethod -eq 'POST') {
                    $body = Read-LumenOpsRequestBody -Request $Request
                    $name = Get-LumenOpsBodyValue $body 'name'
                    $script:LumenOpsState.Targets[$name] = @{
                        addedAt = (Get-Date).ToString('o')
                        label   = Get-LumenOpsBodyValue $body 'label' $name
                    }
                    Write-LumenOpsResponse -Response $Response -Body @{ ok = $true; name = $name }
                }
            }
            '^/api/invoke$' {
                $body = Read-LumenOpsRequestBody -Request $Request
                $plugin = Get-LumenOpsBodyValue $body 'plugin'
                $action = Get-LumenOpsBodyValue $body 'action'
                if (-not $plugin -or -not $action) {
                    Write-LumenOpsResponse -Response $Response -StatusCode 400 -Body @{ error = 'plugin and action required' }
                    return
                }
                $computer = Get-LumenOpsBodyValue $body 'computerName' 'localhost'
                $params = Get-LumenOpsBodyValue $body 'parameters' @{}
                if (-not $params) { $params = @{} }
                $result = Invoke-LumenOpsPluginAction -PluginId $plugin -ActionId $action -ComputerName $computer -Parameters $params
                Write-LumenOpsResponse -Response $Response -Body $result
            }
            '^/api/export/inventory$' {
                $body = Read-LumenOpsRequestBody -Request $Request
                $computer = Get-LumenOpsBodyValue $body 'computerName' 'localhost'
                $inv = Invoke-LumenOpsPluginAction -PluginId 'inventory' -ActionId 'snapshot' -ComputerName $computer
                Write-LumenOpsResponse -Response $Response -Body $inv
            }
            default {
                Write-LumenOpsResponse -Response $Response -StatusCode 404 -Body @{ error = "Unknown API route: $Path" }
            }
        }
    }
    catch {
        Write-LumenOpsLog -Level Error -Message $_.Exception.Message
        Write-LumenOpsResponse -Response $Response -StatusCode 500 -Body @{ error = $_.Exception.Message }
    }
}

function Get-LumenOpsHostPulse {
    param([string]$ComputerName = 'localhost')

    $isLocal = $ComputerName -in @('localhost', 'local', '.', $env:COMPUTERNAME, [System.Net.Dns]::GetHostName())
    $ping = $false
    $latencyMs = $null

    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        if ($isLocal) {
            $ping = $true
        }
        else {
            $pingResult = Test-Connection -TargetName $ComputerName -Count 1 -TimeoutSeconds 2 -ErrorAction SilentlyContinue
            $ping = [bool]$pingResult
        }
        $sw.Stop()
        $latencyMs = $sw.ElapsedMilliseconds
    }
    catch {
        $ping = $false
    }

    $os = $null
    $uptime = $null
    try {
        if ($isLocal) {
            $os = if (Get-Command Get-ComputerInfo -ErrorAction SilentlyContinue) {
                (Get-ComputerInfo -Property OsName, OsVersion -ErrorAction SilentlyContinue | Select-Object -First 1)
            } else {
                [pscustomobject]@{ OsName = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription; OsVersion = $PSVersionTable.OS }
            }
            $uptime = (Get-Date) - (Get-Process -Id $PID).StartTime
        }
    }
    catch { }

    [pscustomobject]@{
        host      = $ComputerName
        online    = $ping
        latencyMs = $latencyMs
        os        = if ($os) { "$($os.OsName) $($os.OsVersion)" } else { $null }
        uptime    = if ($uptime) { '{0}d {1}h {2}m' -f $uptime.Days, $uptime.Hours, $uptime.Minutes } else { $null }
        checkedAt = (Get-Date).ToString('o')
    }
}
