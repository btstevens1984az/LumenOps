function Invoke-LumenPlugin_disk_usage {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'usage'
    )

    $script = {
        Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
            $total = $_.Used + $_.Free
            $pct = if ($total -gt 0) { [math]::Round(($_.Used / $total) * 100, 1) } else { 0 }
            [pscustomobject]@{
                Name     = $_.Name
                Root     = $_.Root
                UsedGB   = [math]::Round($_.Used / 1GB, 2)
                FreeGB   = [math]::Round($_.Free / 1GB, 2)
                TotalGB  = [math]::Round($total / 1GB, 2)
                UsedPct  = $pct
            }
        }
    }

    $items = Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
    [pscustomobject]@{ volumes = @($items) }
}

function Invoke-LumenPlugin_disk_pressure {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'pressure'
    )

    $threshold = if ($Parameters['threshold']) { [double]$Parameters['threshold'] } else { 15 }
    $usage = Invoke-LumenPlugin_disk_usage -ComputerName $ComputerName
    $low = @($usage.volumes | Where-Object {
        $freePct = if ($_.TotalGB -gt 0) { (($_.FreeGB / $_.TotalGB) * 100) } else { 100 }
        $freePct -lt $threshold
    })

    [pscustomobject]@{
        thresholdPct = $threshold
        alertCount   = $low.Count
        volumes      = $low
        message      = if ($low.Count -eq 0) { "No volumes under ${threshold}% free." } else { "$($low.Count) volume(s) under pressure." }
    }
}
