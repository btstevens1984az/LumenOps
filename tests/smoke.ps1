$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Import-Module "$root/LumenOps.psd1" -Force

Write-Host "Plugins=$($(Get-LumenOpsPlugin).Count) Actions=$($(Get-LumenOpsAction).Count)"

$modCmds = & (Get-Module LumenOps) { Get-Command Invoke-LumenPlugin_* -ErrorAction SilentlyContinue }
Write-Host "Module plugin functions: $(@($modCmds).Count)"

$null = Start-LumenOps -Port 8787
# Server process is spawned; Start-LumenOps already waits for health

try {
    $invBody = @{ plugin = 'inventory'; action = 'identity'; computerName = 'localhost' } | ConvertTo-Json
    $inv = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8787/api/invoke' -ContentType 'application/json' -Body $invBody
    Write-Host "OK identity=$($inv.Data.Hostname)"

    $probeBody = @{
        plugin       = 'connectivity'
        action       = 'probe'
        computerName = 'localhost'
        parameters   = @{ host = 'localhost' }
    } | ConvertTo-Json -Depth 5
    $probe = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8787/api/invoke' -ContentType 'application/json' -Body $probeBody
    Write-Host "OK probe score=$($probe.Data.score)"

    $pb = (Resolve-Path "$root/Playbooks/examples/health-check.json").Path
    $runBody = @{ path = $pb; computerName = 'localhost' } | ConvertTo-Json
    $run = Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:8787/api/playbooks' -ContentType 'application/json' -Body $runBody
    Write-Host "OK playbook=$($run.Name) steps=$(@($run.Results).Count)"

    $ui = Invoke-WebRequest -Uri 'http://127.0.0.1:8787/' -UseBasicParsing
    Write-Host "OK UI status=$($ui.StatusCode) bytes=$($ui.Content.Length)"
}
finally {
    Stop-LumenOps
}
