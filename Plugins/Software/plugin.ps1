function Invoke-LumenPlugin_software_installed {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'installed'
    )

    $script = {
        $apps = [System.Collections.Generic.List[object]]::new()

        if (Get-Command Get-Package -ErrorAction SilentlyContinue) {
            try {
                Get-Package -ErrorAction SilentlyContinue |
                    Select-Object -First 200 Name, Version, ProviderName, Source |
                    ForEach-Object { $apps.Add($_) }
            }
            catch { }
        }

        if ($apps.Count -eq 0 -and (Get-Command Get-ItemProperty -ErrorAction SilentlyContinue)) {
            $paths = @(
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            foreach ($p in $paths) {
                try {
                    Get-ItemProperty $p -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName } |
                        Select-Object @{n='Name';e={$_.DisplayName}}, @{n='Version';e={$_.DisplayVersion}}, @{n='Publisher';e={$_.Publisher}} |
                        ForEach-Object { $apps.Add($_) }
                }
                catch { }
            }
        }

        if ($apps.Count -eq 0) {
            $apps.Add([pscustomobject]@{
                Name    = 'PowerShell'
                Version = $PSVersionTable.PSVersion.ToString()
                Note    = 'Limited inventory on this platform — full app list requires Windows.'
            })
        }

        [pscustomobject]@{
            count = $apps.Count
            items = @($apps | Sort-Object Name | Select-Object -First 250)
        }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script
}
