function Invoke-LumenPlugin_network_adapters {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'adapters'
    )

    $script = {
        $configs = @()
        if (Get-Command Get-NetIPConfiguration -ErrorAction SilentlyContinue) {
            $configs = Get-NetIPConfiguration -ErrorAction SilentlyContinue | ForEach-Object {
                [pscustomobject]@{
                    Interface = $_.InterfaceAlias
                    Status    = $_.NetAdapter.Status
                    IPv4      = @($_.IPv4Address.IPAddress) -join ', '
                    IPv6      = @($_.IPv6Address.IPAddress | Select-Object -First 2) -join ', '
                    Gateway   = @($_.IPv4DefaultGateway.NextHop) -join ', '
                    DNS       = @($_.DNSServer.ServerAddresses | Select-Object -First 4) -join ', '
                }
            }
        }
        else {
            $configs = @(([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces()) | ForEach-Object {
                $props = $_.GetIPProperties()
                [pscustomobject]@{
                    Interface = $_.Name
                    Status    = $_.OperationalStatus.ToString()
                    IPv4      = @($props.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | ForEach-Object { $_.Address.ToString() }) -join ', '
                    IPv6      = @($props.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetworkV6' } | Select-Object -First 2 | ForEach-Object { $_.Address.ToString() }) -join ', '
                    Gateway   = @($props.GatewayAddresses | ForEach-Object { $_.Address.ToString() }) -join ', '
                    DNS       = @($props.DnsAddresses | Select-Object -First 4 | ForEach-Object { $_.ToString() }) -join ', '
                }
            })
        }
        [pscustomobject]@{ adapters = @($configs) }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}

function Invoke-LumenPlugin_network_listeners {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'listeners'
    )

    $script = {
        $items = @()
        if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
            $items = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                Sort-Object LocalPort |
                Select-Object -First 100 @(
                    'LocalAddress', 'LocalPort', 'OwningProcess',
                    @{n='Process';e={ try { (Get-Process -Id $_.OwningProcess -ErrorAction Stop).ProcessName } catch { '?' } }}
                )
        }
        else {
            $items = @([pscustomobject]@{ note = 'Get-NetTCPConnection unavailable — use Windows PowerShell / PS 7 on Windows for listeners.' })
        }
        [pscustomobject]@{ listeners = @($items) }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}
