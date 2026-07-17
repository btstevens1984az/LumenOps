# Plugin contract

Every LumenOps plugin is a folder under `Plugins/` with two files.

## plugin.json

| Field | Required | Description |
|---|---|---|
| `id` | yes | Lowercase id used in function names and API (`mytool`) |
| `name` | yes | Display name |
| `description` | yes | One-line summary |
| `icon` | no | Icon key (`cpu`, `gears`, `network`, `shield`, …) |
| `category` | yes | Grouping in UI / palette |
| `version` | yes | SemVer string |
| `actions[]` | yes | List of actions |

### Action object

| Field | Required | Description |
|---|---|---|
| `id` | yes | Action id |
| `name` | yes | Display name |
| `description` | no | Palette subtitle |
| `keywords` | no | Search terms |
| `confirm` | no | Prompt before run |
| `destructive` | no | Marks risky actions |
| `icon` | no | Override plugin icon |

## plugin.ps1

Export one function per action:

```powershell
function Invoke-LumenPlugin_<id>_<action> {
    param(
        [string]$ComputerName = 'localhost',
        [hashtable]$Parameters = @{},
        [string]$ActionId = '<action>'
    )
    # return any JSON-serializable object
}
```

Prefer `Invoke-LumenOpsRemote` so the same plugin works locally and over remoting.

## Tips that get stars

- Return **structured objects**, not format-table strings.
- Keep actions **small and composable** — playbooks stitch them together.
- Document required `Parameters` in the action description.
- Never log secrets.
