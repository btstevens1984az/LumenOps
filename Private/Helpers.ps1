function Write-LumenOpsLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Info', 'Success', 'Warn', 'Error', 'Action')]
        [string]$Level = 'Info',
        [string]$Target = 'local',
        [string]$Action = $null
    )

    $entry = [pscustomobject]@{
        Timestamp = (Get-Date).ToString('o')
        Level     = $Level
        Target    = $Target
        Action    = $Action
        Message   = $Message
    }

    [void]$script:LumenOpsState.ActionLog.Add($entry)

    while ($script:LumenOpsState.ActionLog.Count -gt 500) {
        $script:LumenOpsState.ActionLog.RemoveAt(0)
    }
}

function ConvertTo-LumenOpsJson {
    param([Parameter(ValueFromPipeline)]$InputObject)
    process {
        $InputObject | ConvertTo-Json -Depth 8 -Compress:$false
    }
}

function Get-LumenOpsUiRoot {
    Join-Path $script:LumenOpsRoot 'UI'
}

function Test-LumenOpsIsWindows {
    $IsWindows -or ($PSVersionTable.PSEdition -eq 'Desktop') -or
        [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
            [System.Runtime.InteropServices.OSPlatform]::Windows
        )
}

function Invoke-LumenOpsRemote {
    <#
    .SYNOPSIS
        Runs a scriptblock locally or via Invoke-Command when a remote target is set.
    #>
    param(
        [Parameter(Mandatory)][scriptblock]$ScriptBlock,
        [string]$ComputerName,
        [hashtable]$ArgumentList = @{}
    )

    $target = if ([string]::IsNullOrWhiteSpace($ComputerName) -or $ComputerName -in @('localhost', 'local', '.', $env:COMPUTERNAME)) {
        $null
    } else {
        $ComputerName
    }

    if (-not $target) {
        return & $ScriptBlock @ArgumentList
    }

    if (-not (Get-Command Invoke-Command -ErrorAction SilentlyContinue)) {
        throw "Remote execution requires PowerShell remoting (Invoke-Command)."
    }

    $params = @{
        ComputerName = $target
        ScriptBlock  = $ScriptBlock
        ErrorAction  = 'Stop'
    }

    if ($ArgumentList.Count -gt 0) {
        $params.ArgumentList = @($ArgumentList.Values)
    }

    Invoke-Command @params
}

function Get-LumenOpsContentType {
    param([string]$Extension)
    switch ($Extension.ToLowerInvariant()) {
        '.html' { 'text/html; charset=utf-8' }
        '.css'  { 'text/css; charset=utf-8' }
        '.js'   { 'application/javascript; charset=utf-8' }
        '.json' { 'application/json; charset=utf-8' }
        '.svg'  { 'image/svg+xml' }
        '.png'  { 'image/png' }
        '.ico'  { 'image/x-icon' }
        '.woff2'{ 'font/woff2' }
        default { 'application/octet-stream' }
    }
}

function Read-LumenOpsRequestBody {
    param([System.Net.HttpListenerRequest]$Request)

    if (-not $Request.HasEntityBody) { return @{} }

    $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
    try {
        $raw = $reader.ReadToEnd()
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        return $raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    }
    finally {
        $reader.Dispose()
    }
}

function Get-LumenOpsBodyValue {
    param(
        $Body,
        [Parameter(Mandatory)][string]$Name,
        $Default = $null
    )

    if ($null -eq $Body) { return $Default }

    if ($Body -is [System.Collections.IDictionary]) {
        if ($Body.ContainsKey($Name)) { return $Body[$Name] }
        return $Default
    }

    $prop = $Body.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    return $Default
}

function Write-LumenOpsResponse {
    param(
        [System.Net.HttpListenerResponse]$Response,
        [int]$StatusCode = 200,
        [string]$ContentType = 'application/json; charset=utf-8',
        [object]$Body
    )

    $Response.StatusCode = $StatusCode
    $Response.ContentType = $ContentType
    $Response.Headers.Add('Cache-Control', 'no-store')
    $Response.Headers.Add('Access-Control-Allow-Origin', '*')
    $Response.Headers.Add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
    $Response.Headers.Add('Access-Control-Allow-Headers', 'Content-Type')

    if ($null -eq $Body) {
        $Response.Close()
        return
    }

    $bytes = if ($Body -is [byte[]]) {
        $Body
    } elseif ($ContentType -like 'application/json*') {
        [System.Text.Encoding]::UTF8.GetBytes(($Body | ConvertTo-Json -Depth 10))
    } elseif ($Body -is [string]) {
        [System.Text.Encoding]::UTF8.GetBytes($Body)
    } else {
        [System.Text.Encoding]::UTF8.GetBytes([string]$Body)
    }

    $Response.ContentLength64 = $bytes.Length
    $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Response.Close()
}
