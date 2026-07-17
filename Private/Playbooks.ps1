function Invoke-LumenOpsPlaybookFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$ComputerName = 'localhost',
        [hashtable]$Variables = @{}
    )

    if (-not (Test-Path $Path)) { throw "Playbook not found: $Path" }

    $raw = Get-Content -Raw -Path $Path
    $playbook = if ($Path -match '\.ya?ml$') {
        # Minimal YAML-ish JSON hybrid: prefer .json playbooks; YAML files must be JSON-compatible for v1
        $raw | ConvertFrom-Json -AsHashtable
    } else {
        $raw | ConvertFrom-Json -AsHashtable
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $targets = @()

    if ($playbook.ContainsKey('targets') -and $playbook.targets) {
        $targets = @($playbook.targets)
    }
    elseif ($ComputerName) {
        $targets = @($ComputerName)
    }
    else {
        $targets = @('localhost')
    }

    Write-LumenOpsLog -Level Info -Action 'playbook' -Message "Starting playbook '$($playbook.name)' on $($targets -join ', ')"

    foreach ($target in $targets) {
        foreach ($step in @($playbook.steps)) {
            $stepName = if ($step.name) { $step.name } else { "$($step.plugin).$($step.action)" }
            try {
                $params = @{}
                if ($step.ContainsKey('parameters') -and $step.parameters) {
                    foreach ($key in $step.parameters.Keys) {
                        $val = $step.parameters[$key]
                        if ($val -is [string] -and $val -match '^\$\{(.+)\}$') {
                            $varName = $Matches[1]
                            $val = if ($Variables.ContainsKey($varName)) { $Variables[$varName] } else { $val }
                        }
                        $params[$key] = $val
                    }
                }

                $outcome = Invoke-LumenOpsPluginAction -PluginId $step.plugin -ActionId $step.action -ComputerName $target -Parameters $params
                $results.Add([pscustomobject]@{
                    Target  = $target
                    Step    = $stepName
                    Status  = 'ok'
                    Result  = $outcome
                })
            }
            catch {
                $results.Add([pscustomobject]@{
                    Target  = $target
                    Step    = $stepName
                    Status  = 'failed'
                    Error   = $_.Exception.Message
                })
                if ($playbook.abortOnError) { break }
            }
        }
    }

    Write-LumenOpsLog -Level Success -Action 'playbook' -Message "Playbook '$($playbook.name)' finished"

    return [pscustomobject]@{
        Name      = $playbook.name
        Timestamp = (Get-Date).ToString('o')
        Results   = $results
    }
}

function Get-LumenOpsPlaybooks {
    $root = Join-Path $script:LumenOpsRoot 'Playbooks'
    Get-ChildItem -Path $root -Recurse -Include *.json, *.playbook.json -ErrorAction SilentlyContinue |
        ForEach-Object {
            try {
                $meta = Get-Content -Raw $_.FullName | ConvertFrom-Json
                [pscustomobject]@{
                    Name        = $meta.name
                    Description = $meta.description
                    Path        = $_.FullName
                    Relative    = $_.FullName.Substring($root.Length).TrimStart('\', '/')
                    Targets     = @($meta.targets)
                    StepCount   = @($meta.steps).Count
                }
            }
            catch { }
        }
}
