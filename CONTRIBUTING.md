# Contributing to LumenOps

Thank you — this project is meant to be owned by the PowerShell community.

## Ways to contribute

1. **Plugins** — the highest-impact contribution. See [docs/PLUGINS.md](docs/PLUGINS.md).
2. **Playbooks** — real-world recipes under `Playbooks/examples/`.
3. **UI polish** — accessibility, motion, density options.
4. **Docs & screenshots** — help new admins fall in love in 60 seconds.

## Development

```powershell
Import-Module ./LumenOps.psd1 -Force
Start-LumenOps -OpenBrowser
# edit plugins / UI, then:
Stop-LumenOps
Import-Module ./LumenOps.psd1 -Force
Start-LumenOps -OpenBrowser
```

## PR guidelines

- Keep the default bind address on localhost.
- Prefer PowerShell 7 patterns; avoid Windows-only APIs without a graceful fallback message.
- Don’t commit secrets, tokens, or environment dumps.
- Match the existing tone: direct, admin-friendly, a little cinematic — never cluttered.

## Code of conduct

Be kind. Assume best intent. This is a tool for tired sysadmins at 2 a.m. — leave it better than you found it.
