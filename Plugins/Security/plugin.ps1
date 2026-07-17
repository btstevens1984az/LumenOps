function Invoke-LumenPlugin_security_pulse {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'pulse'
    )

    $script = {
        $signals = [System.Collections.Generic.List[object]]::new()

        $signals.Add([pscustomobject]@{
            name   = 'PowerShell Version'
            status = if ($PSVersionTable.PSVersion.Major -ge 7) { 'good' } else { 'warn' }
            detail = $PSVersionTable.PSVersion.ToString()
        })

        $signals.Add([pscustomobject]@{
            name   = 'Execution Policy'
            status = 'info'
            detail = try { (Get-ExecutionPolicy -ErrorAction Stop).ToString() } catch { 'unknown' }
        })

        if (Get-Command Get-NetFirewallProfile -ErrorAction SilentlyContinue) {
            Get-NetFirewallProfile -ErrorAction SilentlyContinue | ForEach-Object {
                $signals.Add([pscustomobject]@{
                    name   = "Firewall ($($_.Name))"
                    status = if ($_.Enabled) { 'good' } else { 'warn' }
                    detail = if ($_.Enabled) { 'Enabled' } else { 'Disabled' }
                })
            }
        }
        else {
            $signals.Add([pscustomobject]@{
                name   = 'Firewall'
                status = 'info'
                detail = 'Firewall cmdlets unavailable on this host'
            })
        }

        if (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) {
            try {
                $admins = Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
                    Select-Object -ExpandProperty Name
                $signals.Add([pscustomobject]@{
                    name   = 'Local Administrators'
                    status = 'info'
                    detail = ($admins -join ', ')
                })
            }
            catch { }
        }

        $signals.Add([pscustomobject]@{
            name   = 'OS Description'
            status = 'info'
            detail = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        })

        [pscustomobject]@{
            signals   = @($signals)
            checkedAt = (Get-Date).ToString('o')
        }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}

function Invoke-LumenPlugin_security_password {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'password'
    )

    $length = if ($Parameters['length']) { [int]$Parameters['length'] } else { 24 }
    $chars = (48..57) + (65..90) + (97..122) + (33,35,36,37,38,42,43,45,61,63,64)
    $password = -join ($chars | Get-Random -Count $length | ForEach-Object { [char]$_ })

    # Intentionally do NOT write password to action log
    [pscustomobject]@{
        length    = $length
        password  = $password
        generated = (Get-Date).ToString('o')
        note      = 'Generated locally. Copy now — LumenOps does not store this value.'
    }
}
