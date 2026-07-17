# Security

LumenOps is a local admin console. Please report vulnerabilities privately.

## Reporting

Email the maintainer via GitHub or open a private security advisory on the repository.

## Scope

- Binding should remain on loopback (`127.0.0.1`) by default.
- Do not propose features that exfiltrate credentials or disable confirmation on destructive actions without explicit opt-in.
- Generated passwords must never be written to disk or the activity log.
