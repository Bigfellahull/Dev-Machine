# dev-machine

`dev-machine` is the source of truth for reproducible Ubuntu development
workstations hosted by OrbStack on separate work and personal Mac minis.

The Linux machine is disposable. Repositories, SDKs, build tools, AI coding
CLIs and normal development commands live in Ubuntu. OrbStack's native Docker
environment on macOS runs profile-scoped, project-isolated database
infrastructure.

## Boundaries

- macOS: OrbStack, Tailscale, Remote Login, and Parallels on the work mini.
- Ubuntu: development tools, repositories, SDKs and AI coding CLIs.
- OrbStack Docker: shared image/cache storage but separate project data.
- MacBook Air: Zed, Ghostty, Tailscale and OpenSSH configuration.
- Secrets and user identities: never committed.
- Parallels: entirely outside this repository.

The provisioning repository is the one deliberate host-side source checkout:
it must exist on macOS to create a machine. Ordinary project repositories live
under `~/code` inside Ubuntu.

## Host lifecycle

On a new mini after installing and starting OrbStack:

```bash
cp config/host.env.example config/local/host.env
bin/dev create work --dry-run
bin/dev create work
```

Use `personal` on the personal mini. `create` builds the pinned Ubuntu machine,
waits for cloud-init, runs the generic bootstrap, and mirrors this repository to
`~/code/dev-machine` inside Ubuntu. Provisioning upgrades Ubuntu, uses mise for
.NET 10, the latest Go, Node.js, Python, Starship and standalone developer tools,
and installs the three AI CLIs. The work profile also adds stable Rust,
WeasyPrint and the .NET `wasm-tools` workload through mise. Other commands are:

```bash
bin/dev provision work
bin/dev clone work risky-sdk-change
bin/dev destroy-experiment work risky-sdk-change
bin/dev rebuild work
bin/dev destroy work
bin/dev list
```

Destructive commands resolve exactly one machine. They require typed
confirmation unless `--yes` is explicitly supplied, and they never use globs.
Use `--dry-run` before lifecycle changes and run end-to-end provisioning tests
only against disposable machines, never an existing workstation.
An existing Ubuntu Git checkout is never overwritten by host-side provisioning;
pull and commit it normally inside Ubuntu after provisioning seeds it.

## Post-bootstrap state

Inside Ubuntu:

```bash
cp ~/code/dev-machine/docker/db.env.example ~/.config/dev-machine/db.env
chmod 600 ~/.config/dev-machine/db.env
# Edit the placeholder local-only passwords before starting databases.

gh auth login
git config --global user.name "Your Name"
git config --global user.email "your-private-address"
codex
claude
grok
local-dev-tls import /path/to/profile-matched-handoff
bootstrap/verify.sh
```

Authentication is intentionally interactive and separate from provisioning.
Use the appropriate credentials independently on the work and personal hosts.
Interactive Bash sessions use the managed Starship prompt. AI tools receive
shared global instructions, the shared `codebase-sweep` skill, and the
Codex-only `collab` skill without copying authentication or runtime state.
The TLS import is also an explicit commissioning action because it installs a
profile-specific public CA and private leaf key. See [local development
TLS](docs/local-dev-tls.md).

## Database workflow

Run `db` from a project directory so its Git repository name becomes the
logical isolation boundary:

```bash
db start postgres
db status
db connection postgres
db reset postgres
```

The personal profile exposes PostgreSQL only. The work profile additionally
exposes SQL Server and Redis, so `db start mssql` and `db start redis` are
available only there. `db --help` reports the engines enabled on the current
machine.

Use `--project NAME` when the current directory is not the desired project.
Applications in Ubuntu connect to `docker.orb.internal` and the configured
published port. See [Docker architecture](docs/docker.md).

## Remote workflow

The recommended path is:

```text
Air --OpenSSH/Tailscale--> mini --ProxyJump/localhost:32222--> OrbStack Ubuntu
```

After commissioning, `ssh work-dev` and `ssh personal-dev` are the same aliases
used by Ghostty and Zed. See [remote access](docs/remote-access.md).

## Verification

Repository-only tests do not create a VM, container, volume or host setting:

```bash
make test
make lint
```

Inside a provisioned Ubuntu machine:

```bash
bootstrap/verify.sh
```

## Documentation

- [Architecture](docs/architecture.md)
- [Bootstrap and authentication](docs/bootstrap.md)
- [Docker and database helpers](docs/docker.md)
- [Local development TLS](docs/local-dev-tls.md)
- [Remote access, Zed, Ghostty and tmux](docs/remote-access.md)
- [Storage and external drive](docs/storage.md)
- [Recovery and rebuilds](docs/recovery.md)
- [Mac mini commissioning checklist](docs/commissioning.md)

## Primary references

- [OrbStack Linux machines](https://docs.orbstack.dev/machines/)
- [OrbStack cloud-init](https://docs.orbstack.dev/machines/cloud-init)
- [OrbStack SSH](https://docs.orbstack.dev/machines/ssh)
- [OrbStack networking](https://docs.orbstack.dev/machines/network)
- [mise installation](https://mise.jdx.dev/installing-mise.html)
- [.NET on Ubuntu](https://learn.microsoft.com/dotnet/core/install/linux-ubuntu-install)
- [Codex CLI](https://learn.chatgpt.com/docs/codex/cli)
- [Claude Code setup](https://code.claude.com/docs/en/getting-started)
- [Grok CLI](https://github.com/xai-org/grok-build/tree/main/crates/codegen/xai-grok-pager/npm/grok)
