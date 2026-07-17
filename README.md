# LumenOps

**The modern PowerShell admin console the community has been waiting for.**

A spiritual successor to [LazyWinAdmin](https://github.com/lazywinadmin/LazyWinAdmin_GUI) — rebuilt from the ground up with a glass UI, remoting-native architecture, a VS Code–style command palette, shareable playbooks, and a drop-in plugin system.

```powershell
Import-Module ./LumenOps.psd1
Start-LumenOps -OpenBrowser
# or just:  lumen
```

Open `http://127.0.0.1:8787` and you’re in.

---

## Why LumenOps?

LazyWinAdmin (2012) proved that PowerShell + a GUI could make day-to-day Windows administration *feel* fast. LumenOps keeps that spirit and throws out the WinForms baggage.

| Then (LazyWinAdmin) | Now (LumenOps) |
|---|---|
| Sapien WinForms, PS 2.0 | PowerShell 7+, local glass web console |
| One machine at a time | Fleet pulse + multi-target playbooks |
| Hard-coded buttons | Discoverable plugins + ⌘K command palette |
| Text dumps in a RichTextBox | Structured JSON you can export, pipe, automate |
| Optional external EXEs | Pure PowerShell plugins the community can ship |

**What’s new for the community (the “never been done quite like this” part):**

1. **Glass console, PowerShell brain** — A beautiful local UI served by `HttpListener`, backed entirely by PowerShell. No Electron. No C# project. Clone → import → go.
2. **Command palette** — Every plugin action is searchable (`⌘K` / `Ctrl+K`). Muscle memory for admins who live in VS Code / Windows Terminal.
3. **Playbooks** — Multi-step JSON recipes (`health-check`, `inventory-export`, `fleet-pulse`) you can version, share, and run against any target.
4. **Plugin marketplace shape** — Drop a folder with `plugin.json` + `plugin.ps1` into `Plugins/` and it appears in the UI. No recompile. No PR required to try it.
5. **Fleet pulse** — Probe ICMP / WinRM / RDP / SMB / HTTP across a list of hosts in one shot.
6. **Security-aware defaults** — Destructive actions confirm; generated passwords never hit the activity log.

---

## Screenshots

> Run `Start-LumenOps -OpenBrowser` and you’ll see the teal glass console: brand-forward hero, plugin rail, live JSON inspector, and command palette.

*(Add your own captures to `/media` after first run — PRs with screenshots are very welcome.)*

---

## Quick start

### Requirements

- **PowerShell 7.0+** ([install](https://aka.ms/powershell))
- Browser (Chrome, Edge, Firefox, Safari)
- Permissions on local or remote targets you manage
- Windows for full CIM/service/event-log coverage (console itself runs cross-platform for UI/dev)

### Install from source

```powershell
git clone https://github.com/btstevens1984az/LumenOps.git
cd LumenOps
Import-Module ./LumenOps.psd1 -Force
Start-LumenOps -OpenBrowser
```

### Optional: current-user install

```powershell
$dest = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell/Modules/LumenOps'
New-Item -ItemType Directory -Force -Path $dest | Out-Null
Copy-Item -Recurse -Force ./* $dest
Import-Module LumenOps -Force
lumen
```

---

## Built-in plugins

| Plugin | What you get |
|---|---|
| **Inventory** | Full snapshot + host identity |
| **Services** | List, auto-start health, start/stop/restart |
| **Processes** | Top consumers + process list |
| **Disk** | Volume usage + storage pressure |
| **Network** | Adapters / IP config + TCP listeners |
| **Connectivity** | Ping + full probe matrix (WinRM, RDP, SMB, HTTP/S) |
| **Software** | Installed applications |
| **Sessions** | Signed-in users / session hints |
| **Event Log** | Recent System errors & warnings |
| **Security** | Hardening pulse + strong password generator |

---

## Command palette

Press **⌘K** (macOS) or **Ctrl+K** (Windows/Linux) and type:

- `disk`
- `auto health`
- `probe`
- `password`
- `inventory`

Enter runs the action against the current **Target** field.

---

## Playbooks

Example — health check:

```powershell
Invoke-LumenOpsPlaybook -Path ./Playbooks/examples/health-check.json -ComputerName SRV01
```

Or click **Playbooks** in the console.

Author your own:

```json
{
  "name": "My Check",
  "description": "Custom recipe",
  "abortOnError": false,
  "targets": ["SRV01", "SRV02"],
  "steps": [
    { "name": "Probe", "plugin": "connectivity", "action": "probe" },
    { "name": "Disk", "plugin": "disk", "action": "pressure", "parameters": { "threshold": 10 } }
  ]
}
```

---

## Write a plugin (5 minutes)

```
Plugins/
  MyTool/
    plugin.json
    plugin.ps1
```

**plugin.json**

```json
{
  "id": "mytool",
  "name": "My Tool",
  "description": "Does a useful thing",
  "icon": "box",
  "category": "Custom",
  "version": "1.0.0",
  "actions": [
    {
      "id": "run",
      "name": "Run",
      "description": "Execute the tool",
      "keywords": ["mytool", "custom"]
    }
  ]
}
```

**plugin.ps1**

```powershell
function Invoke-LumenPlugin_mytool_run {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = 'run'
    )

    Invoke-LumenOpsRemote -ComputerName $ComputerName -ScriptBlock {
        [pscustomobject]@{
            Hello = 'from My Tool'
            When  = (Get-Date).ToString('o')
        }
    }
}
```

Reload the module (or restart the console) — it shows up in the rail and palette automatically.

See [docs/PLUGINS.md](docs/PLUGINS.md) for the full contract.

---

## Module commands

| Command | Purpose |
|---|---|
| `Start-LumenOps` / `lumen` | Launch the glass console |
| `Stop-LumenOps` | Stop the local server |
| `Get-LumenOpsPlugin` | List plugins |
| `Get-LumenOpsAction` | List palette actions |
| `Invoke-LumenOpsPlaybook` | Run a playbook from the CLI |
| `Export-LumenOpsInventory` | Snapshot inventory to JSON |

---

## Architecture

```
Browser (glass UI)
    │  HTTP 127.0.0.1
    ▼
LumenOps HttpListener  ──►  Plugin actions  ──►  local / Invoke-Command
    │
    ├── Playbooks (JSON recipes)
    ├── Activity log (session)
    └── Static UI (HTML/CSS/JS)
```

No cloud dependency. Your admin traffic stays on the box unless *you* target remotes.

---

## Security notes

- The console binds to **127.0.0.1** only.
- Treat playbooks like scripts — review before running against production.
- Password generation is local and intentionally **not** written to the activity log.
- Remote actions use your existing PowerShell remoting trust model.

---

## Roadmap

- [ ] Signed community plugin gallery feed
- [ ] WinRM credential profiles (SecretManagement)
- [ ] Diff two inventory snapshots over time
- [ ] Optional WebView2 desktop shell for a frameless app feel
- [ ] Discord / GitHub Discussions plugin showcases

PRs welcome — especially plugins and playbooks.

---

## Inspired by

[LazyWinAdmin_GUI](https://github.com/lazywinadmin/LazyWinAdmin_GUI) by [Francois-Xavier Cat](https://github.com/lazywinadmin) — thank you for showing the PowerShell world what a friendly admin GUI could be.

---

## License

MIT © 2026 Brandon Stevens — see [LICENSE](LICENSE).

---

<p align="center">
  <b>If LumenOps saves you a remote desktop hop, give it a ⭐</b><br/>
  <sub>Built for the PowerShell community · Share a plugin · Ship a playbook</sub>
</p>
