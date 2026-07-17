function Invoke-LumenPlugin_sessions_users {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'users'
    )

    $script = {
        $sessions = [System.Collections.Generic.List[object]]::new()

        if (Get-Command quser -ErrorAction SilentlyContinue) {
            try {
                $raw = quser 2>$null | Out-String
                $sessions.Add([pscustomobject]@{ source = 'quser'; raw = $raw.Trim() })
            }
            catch { }
        }

        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            try {
                Get-CimInstance Win32_LoggedOnUser -ErrorAction SilentlyContinue |
                    Select-Object -First 40 |
                    ForEach-Object {
                        $sessions.Add([pscustomobject]@{
                            Antecedent = [string]$_.Antecedent
                            Dependent  = [string]$_.Dependent
                        })
                    }
            }
            catch { }
        }

        if ($sessions.Count -eq 0) {
            $sessions.Add([pscustomobject]@{
                User   = if ($env:USER) { $env:USER } else { $env:USERNAME }
                Source = 'environment'
                Note   = 'Detailed session enumeration requires Windows (quser / CIM).'
            })
        }

        [pscustomobject]@{ sessions = @($sessions) }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}
