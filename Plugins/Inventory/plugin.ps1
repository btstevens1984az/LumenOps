function Invoke-LumenPlugin_inventory_snapshot {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'snapshot'
    )

    $script = {
        $osDesc = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
        $arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        $procs = Get-Process -ErrorAction SilentlyContinue
        $drives = Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue | ForEach-Object {
            [pscustomobject]@{
                Name        = $_.Name
                UsedGB      = [math]::Round(($_.Used / 1GB), 2)
                FreeGB      = [math]::Round(($_.Free / 1GB), 2)
                Root        = $_.Root
            }
        }

        $memory = $null
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            try {
                $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction Stop
                $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
                $bios = Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue
                $memory = [pscustomobject]@{
                    TotalGB     = [math]::Round($cs.TotalPhysicalMemory / 1GB, 2)
                    FreeGB      = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
                    Manufacturer= $cs.Manufacturer
                    Model       = $cs.Model
                    Processors  = $cs.NumberOfProcessors
                    LogicalCPUs = $cs.NumberOfLogicalProcessors
                    Domain      = $cs.Domain
                    BiosSerial  = $bios.SerialNumber
                }
                $osName = $os.Caption
                $osVersion = $os.Version
                $lastBoot = $os.LastBootUpTime
            }
            catch {
                $osName = $osDesc
                $osVersion = $PSVersionTable.OS
                $lastBoot = $null
            }
        }
        else {
            $osName = $osDesc
            $osVersion = $PSVersionTable.OS
            $lastBoot = $null
        }

        [pscustomobject]@{
            Hostname     = [System.Net.Dns]::GetHostName()
            User         = $(
                try { [System.Security.Principal.WindowsIdentity]::GetCurrent().Name }
                catch { if ($env:USER) { $env:USER } elseif ($env:USERNAME) { $env:USERNAME } else { 'unknown' } }
            )
            OS           = $osName
            OSVersion    = $osVersion
            Architecture = $arch
            PowerShell   = $PSVersionTable.PSVersion.ToString()
            Edition      = $PSVersionTable.PSEdition
            LastBoot     = $lastBoot
            ProcessCount = @($procs).Count
            Drives       = @($drives)
            Hardware     = $memory
            CollectedAt  = (Get-Date).ToString('o')
        }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}

function Invoke-LumenPlugin_inventory_identity {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'identity'
    )

    $script = {
        [pscustomobject]@{
            Hostname  = [System.Net.Dns]::GetHostName()
            FQDN      = [System.Net.Dns]::GetHostEntry('localhost').HostName
            User      = if ($IsWindows -or $env:USERNAME) { "$env:USERDOMAIN\$env:USERNAME" } else { $env:USER }
            TimeZone  = [System.TimeZoneInfo]::Local.DisplayName
            Culture   = [System.Globalization.CultureInfo]::CurrentCulture.Name
            UtcNow    = (Get-Date).ToUniversalTime().ToString('o')
            LocalNow  = (Get-Date).ToString('o')
        }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}
