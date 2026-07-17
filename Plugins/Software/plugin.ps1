function Invoke-LumenPlugin_software_installed {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'installed'
    )

    $limit = if ($Parameters['limit']) { [int]$Parameters['limit'] } else { 400 }

    $script = {
        param($Take)

        $apps = [System.Collections.Generic.List[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

        function Add-AppRow {
            param(
                [string]$Name,
                [string]$Version = '',
                [string]$Publisher = '',
                [string]$Source = ''
            )
            if ([string]::IsNullOrWhiteSpace($Name)) { return }
            $key = "$Name|$Version"
            if (-not $seen.Add($key)) { return }
            $apps.Add([pscustomobject]@{
                Name      = $Name.Trim()
                Version   = if ($Version) { $Version.Trim() } else { '—' }
                Publisher = if ($Publisher) { $Publisher.Trim() } else { '—' }
                Source    = $Source
            })
        }

        # Windows registry (primary — most complete installed-apps list)
        if (Get-Command Get-ItemProperty -ErrorAction SilentlyContinue) {
            $paths = @(
                'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
            )
            foreach ($p in $paths) {
                try {
                    Get-ItemProperty $p -ErrorAction SilentlyContinue |
                        Where-Object { $_.DisplayName -and -not $_.SystemComponent } |
                        ForEach-Object {
                            Add-AppRow -Name $_.DisplayName -Version $_.DisplayVersion -Publisher $_.Publisher -Source 'Registry'
                        }
                }
                catch { }
            }
        }

        # PackageManagement / WinGet-style packages (supplement)
        if (Get-Command Get-Package -ErrorAction SilentlyContinue) {
            try {
                Get-Package -ErrorAction SilentlyContinue | ForEach-Object {
                    Add-AppRow -Name $_.Name -Version ([string]$_.Version) -Publisher ([string]$_.ProviderName) -Source 'Package'
                }
            }
            catch { }
        }

        # macOS / Linux Applications folders
        foreach ($appRoot in @('/Applications', "$env:HOME/Applications", '/System/Applications')) {
            if (Test-Path $appRoot) {
                try {
                    Get-ChildItem -Path $appRoot -Filter '*.app' -Directory -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            $ver = ''
                            try {
                                if (Test-Path '/usr/bin/mdls') {
                                    $ver = & /usr/bin/mdls -name kMDItemVersion -raw $_.FullName 2>$null
                                    if ($ver -eq '(null)') { $ver = '' }
                                }
                            }
                            catch { $ver = '' }
                            $appName = $_.Name -replace '\.app$', ''
                            Add-AppRow -Name $appName -Version ([string]$ver) -Publisher '—' -Source 'Applications'
                        }
                }
                catch { }
            }
        }

        # Homebrew
        if (Get-Command brew -ErrorAction SilentlyContinue) {
            try {
                $brewOut = brew list --versions 2>$null
                foreach ($line in @($brewOut)) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $parts = ($line -split '\s+', 2)
                    Add-AppRow -Name $parts[0] -Version $(if ($parts.Count -gt 1) { $parts[1] } else { '' }) -Source 'Homebrew'
                }
            }
            catch { }
        }

        # Always include runtime facts so the list is never empty of real data
        Add-AppRow -Name 'PowerShell' -Version $PSVersionTable.PSVersion.ToString() -Publisher 'Microsoft' -Source 'Runtime'
        if ($PSVersionTable.OS) {
            Add-AppRow -Name 'Operating System' -Version ([string]$PSVersionTable.OS) -Publisher '' -Source 'Runtime'
        }

        $sorted = @($apps | Sort-Object Name, Version | Select-Object -First $Take)

        [pscustomobject]@{
            title     = 'Installed software'
            count     = $sorted.Count
            platform  = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
            items     = $sorted
            collected = (Get-Date).ToString('o')
        }
    }

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock $script -ArgumentList @{ Take = $limit }
}
