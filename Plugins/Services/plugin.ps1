function Invoke-LumenPlugin_services_list {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'list'
    )

    $script = {
        if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
            return @{ error = 'Get-Service is not available on this platform.'; items = @() }
        }
        $items = Get-Service -ErrorAction SilentlyContinue | Sort-Object Status, DisplayName | Select-Object -First 200 @(
            'Name', 'DisplayName', 'Status', 'StartType'
        )
        [pscustomobject]@{ count = @($items).Count; items = @($items) }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}

function Invoke-LumenPlugin_services_autoHealth {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'autoHealth'
    )

    $script = {
        if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
            return @{ error = 'Get-Service is not available on this platform.'; items = @() }
        }
        $broken = Get-Service -ErrorAction SilentlyContinue |
            Where-Object { $_.StartType -eq 'Automatic' -and $_.Status -ne 'Running' } |
            Select-Object Name, DisplayName, Status, StartType
        [pscustomobject]@{
            unhealthy = @($broken).Count
            items     = @($broken)
            message   = if (@($broken).Count -eq 0) { 'All Automatic services are running.' } else { "$($broken.Count) Automatic service(s) not running." }
        }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}

function Invoke-LumenPlugin_services_control {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'control'
    )

    $name = $Parameters['name']
    $op = $Parameters['operation']
    if (-not $name -or -not $op) { throw "parameters.name and parameters.operation (Start|Stop|Restart) are required" }

    $script = {
        param($ServiceName, $Operation)
        $svc = Get-Service -Name $ServiceName -ErrorAction Stop
        switch ($Operation) {
            'Start'   { Start-Service -Name $ServiceName; break }
            'Stop'    { Stop-Service -Name $ServiceName -Force; break }
            'Restart' { Restart-Service -Name $ServiceName -Force; break }
            default   { throw "Unknown operation: $Operation" }
        }
        $after = Get-Service -Name $ServiceName
        [pscustomobject]@{
            Name      = $after.Name
            Status    = $after.Status.ToString()
            Operation = $Operation
        }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script -ArgumentList @{
        ServiceName = $name
        Operation   = $op
    }
}
