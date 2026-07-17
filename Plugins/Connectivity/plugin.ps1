function Invoke-LumenPlugin_connectivity_ping {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'ping'
    )

    $target = if ($Parameters['host']) { $Parameters['host'] } else { $ComputerName }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $ok = $false
    try {
        if ($target -in @('localhost', '127.0.0.1', '::1', '.')) {
            $ok = $true
        }
        else {
            $r = Test-Connection -TargetName $target -Count 2 -TimeoutSeconds 2 -ErrorAction SilentlyContinue
            $ok = [bool]$r
        }
    }
    catch { $ok = $false }
    $sw.Stop()

    [pscustomobject]@{
        host      = $target
        online    = $ok
        latencyMs = $sw.ElapsedMilliseconds
        checkedAt = (Get-Date).ToString('o')
    }
}

function Invoke-LumenPlugin_connectivity_probe {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'probe'
    )

    $target = if ($Parameters['host']) { $Parameters['host'] } else { $ComputerName }

    function Test-TcpPort {
        param([string]$HostName, [int]$Port, [int]$TimeoutMs = 1500)
        try {
            $client = [System.Net.Sockets.TcpClient]::new()
            $iar = $client.BeginConnect($HostName, $Port, $null, $null)
            $ok = $iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false)
            if ($ok -and $client.Connected) {
                $client.EndConnect($iar)
                $client.Close()
                return $true
            }
            $client.Close()
            return $false
        }
        catch { return $false }
    }

    $hostForTcp = if ($target -in @('localhost', '.')) { '127.0.0.1' } else { $target }

    $icmp = Invoke-LumenPlugin_connectivity_ping -ComputerName $ComputerName -Parameters @{ host = $target }

    $dnsOk = $false
    $resolved = @()
    try {
        $resolved = @([System.Net.Dns]::GetHostAddresses($hostForTcp) | ForEach-Object { $_.ToString() })
        $dnsOk = $resolved.Count -gt 0
    }
    catch { $dnsOk = $false }

    $checks = @(
        [pscustomobject]@{ name = 'ICMP'; ok = [bool]$icmp.online; detail = "$($icmp.latencyMs) ms" }
        [pscustomobject]@{ name = 'DNS';  ok = $dnsOk; detail = ($resolved -join ', ') }
        [pscustomobject]@{ name = 'WinRM (5985)'; ok = Test-TcpPort $hostForTcp 5985; detail = 'HTTP listener' }
        [pscustomobject]@{ name = 'WinRM (5986)'; ok = Test-TcpPort $hostForTcp 5986; detail = 'HTTPS listener' }
        [pscustomobject]@{ name = 'RDP (3389)';   ok = Test-TcpPort $hostForTcp 3389; detail = 'Remote Desktop' }
        [pscustomobject]@{ name = 'SMB (445)';    ok = Test-TcpPort $hostForTcp 445;  detail = 'File shares' }
        [pscustomobject]@{ name = 'HTTP (80)';    ok = Test-TcpPort $hostForTcp 80;   detail = 'Web' }
        [pscustomobject]@{ name = 'HTTPS (443)';  ok = Test-TcpPort $hostForTcp 443;  detail = 'TLS Web' }
    )

    $passed = @($checks | Where-Object ok).Count
    [pscustomobject]@{
        host      = $target
        score     = "$passed / $($checks.Count)"
        passed    = $passed
        total     = $checks.Count
        checks    = $checks
        checkedAt = (Get-Date).ToString('o')
    }
}
