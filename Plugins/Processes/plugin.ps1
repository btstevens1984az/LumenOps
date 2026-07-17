function Invoke-LumenPlugin_processes_top {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'top'
    )

    $limit = if ($Parameters['limit']) { [int]$Parameters['limit'] } else { 25 }

    $script = {
        param($Take)
        Get-Process -ErrorAction SilentlyContinue |
            Sort-Object WorkingSet64 -Descending |
            Select-Object -First $Take @(
                @{n='Name';e={$_.ProcessName}},
                'Id',
                @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
                @{n='CPU';e={$_.CPU}},
                @{n='StartTime';e={$_.StartTime}}
            )
    }

    $items = Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script -ArgumentList @{ Take = $limit }
    [pscustomobject]@{ items = @($items) }
}

function Invoke-LumenPlugin_processes_list {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'list'
    )

    $script = {
        Get-Process -ErrorAction SilentlyContinue |
            Sort-Object ProcessName |
            Select-Object -First 150 @(
                @{n='Name';e={$_.ProcessName}},
                'Id',
                @{n='WS_MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},
                @{n='Path';e={try{$_.Path}catch{$null}}}
            )
    }

    $items = Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
    [pscustomobject]@{ count = @($items).Count; items = @($items) }
}
