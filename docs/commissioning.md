# Mac mini commissioning checklist

Run work and personal commissioning independently. Do not share local config,
keys, tokens or database volumes.

## Host

- Apply macOS updates and choose stable hostnames.
- Install/start OrbStack and Tailscale; enable MagicDNS.
- Enable macOS Remote Login for the intended account only.
- On work, install Parallels independently.
- Confirm no Docker Desktop, Colima or host development toolchain is required.
- Run `orbctl version`, `orbctl doctor`, `docker context show` and
  `docker compose version`.
- Copy `config/host.env.example` to ignored `config/local/host.env` and tune
  resource ceilings for the purchased hardware.

## Primary machine

```bash
bin/dev create work --dry-run
bin/dev create work
```

- Confirm Ubuntu 26.04 and ARM64.
- Run `bootstrap/verify.sh` twice; the second run must remain clean.
- Confirm `swapon --show` reports active swap and
  `systemctl --user show -p DefaultOOMPolicy` reports `continue`.
- Configure private Git identity and authenticate `gh`, Codex, Claude and Grok.
- Export the profile-specific local TLS handoff on the matching mini, transfer it through an authenticated local channel, and run `local-dev-tls import /path/to/handoff` inside Ubuntu.
- Run `local-dev-tls verify`, then remove the exact temporary handoff from both the mini and Ubuntu.
- Clone representative .NET, Go, Node.js and Python repositories under
  `~/code` on both profiles.
- Validate the shared certificate with representative Caddy, Go, .NET/Aspire and Next.js development servers, including a browser on every client Mac that will use them.
- Confirm the browser clients trust only the matching public root and that no CA private key left its issuing mini.
- On work, also clone a representative Rust repository and exercise the
  work-only PDF/media toolchain.
- On work, confirm the Azure Artifacts Credential Provider appears in
  `dotnet tool list --global`, then authenticate a representative private feed
  with `dotnet restore --interactive`.
- Run restore/build/test workflows for each applicable ecosystem.

## Infrastructure

- Create the private database environment file.
- On both profiles, start PostgreSQL and test it from Ubuntu through
  `docker.orb.internal`.
- On work only, start Redis and SQL Server. Record SQL Server translation
  performance and verify representative schema/backup/restore behavior; retain
  the unsupported-emulation warning in the commissioning record.
- On personal, confirm `db --help` lists only PostgreSQL and rejects SQL Server
  and Redis.
- Confirm project B receives different containers/volumes from project A.
- Confirm a database reset cannot remove another project or engine.

## Remote client

- Authorize the correct Air key in macOS and OrbStack SSH.
- Test `ssh work-dev` on the LAN and away through Tailscale.
- Open a project through Zed using the same alias.
- Start a Ghostty SSH session and `tmux new -As dev`; disconnect and reattach.
- Confirm Starship symbols render and Claude, Codex and Grok report full-colour terminal support inside and outside tmux.
- Repeat with entirely separate key/config state for personal.

## Storage and recovery

- Format/name the work external drive and create the documented layout.
- Disconnect it and verify `work-dev` still operates.
- Confirm backup/export scripts fail loudly while it is absent.
- Create and inspect a machine export after reconnecting it.
- Restore a representative PostgreSQL dump and SQL Server backup.

## Destructive acceptance test

After all important source and database state is authoritative elsewhere:

```bash
bin/dev rebuild work
```

Use `bin/dev rebuild personal` for the personal acceptance test.

Reauthenticate, clone the test repositories, build/test them, reconnect to
project infrastructure and repeat remote Zed/Ghostty checks. A successful clean
rebuild is the proof that no undocumented VM state is required.

Repeat the common checks independently with `personal`. Confirm that Rust,
WeasyPrint, the media/PDF utilities, Azure CLI, the Azure Artifacts Credential
Provider, SQL Server and Redis remain absent, and omit the work-only
external-drive checks.
