function Invoke-LumenPlugin_eventlog_errors {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'errors'
    )

    $take = if ($Parameters['limit']) { [int]$Parameters['limit'] } else { 40 }

    $script = {
        param($Limit)
        if (Get-Command Get-WinEvent -ErrorAction SilentlyContinue) {
            try {
                $events = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 2, 3 } -MaxEvents $Limit -ErrorAction Stop |
                    Select-Object TimeCreated, Id, LevelDisplayName, ProviderName, @{n='Message';e={ $_.Message.Split("`n")[0].Substring(0, [Math]::Min(180, $_.Message.Split("`n")[0].Length)) }}
                return [pscustomobject]@{ source = 'WinEvent'; items = @($events) }
            }
            catch {
                return [pscustomobject]@{ source = 'WinEvent'; error = $_.Exception.Message; items = @() }
            }
        }

        [pscustomobject]@{
            source  = 'unavailable'
            message = 'Get-WinEvent requires Windows. On other platforms, use remote targets.'
            items   = @()
        }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script -ArgumentList @{ Limit = $take }
}
