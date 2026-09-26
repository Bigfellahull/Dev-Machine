# dev-machine

Reproducible Ubuntu development workstations hosted by OrbStack on separate
work and personal Mac minis. Repositories, SDKs, build tools and AI coding CLIs
live in Ubuntu; OrbStack's native Docker engine on macOS runs the databases.

## Start here

Use the [step-by-step VM setup guide](docs/setup.md) to create and bootstrap
one VM, configure Git and provider access, import HTTPS certificates, prepare
projects/databases, and verify it from the Air. Every step identifies the
machine on which its commands run.

For a new installation of **all Macs and VMs**, start with the
[Mac-Bootstrap end-to-end guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/setup.md).
It puts host setup, VM creation, certificate transfer and Air clients in one
order. If the VM already exists, resume at [VM verification](docs/setup.md#2-open-the-vm-and-check-provisioning);
do not recreate it.

| Profile | VM | Installed automatically |
|---|---|---|
| Both | — | .NET 10, Go, Node.js, Python, mise, Git/GitHub tools, shell tools, tmux, Codex, Claude, Grok and PostgreSQL helpers |
| Work | `work-dev` | Rust, Azure CLI, Azure Artifacts Credential Provider, SqlPackage, sqlcmd, WASM workload, PDF/media tools, SQL Server/Redis helpers |
| Personal | `personal-dev` | Railway CLI and the shared `use-railway` skill |

Provisioning installs capability. Identities, authentication, certificates and
project configuration still need the setup guide. Windows and project-specific
configuration can be deferred until the corresponding workflow is needed.

## Updating and lifecycle commands

Run lifecycle commands **on the matching Mac mini, from this checkout**:

```bash
bin/dev --help
bin/dev provision work --dry-run
bin/dev provision work
bin/dev list
```

Use `personal` on the personal mini. Review and update the host checkout before
provisioning. An existing Ubuntu checkout is left unchanged: update it
separately before running its verifier. See [updating a provisioned
machine](docs/bootstrap.md#updating-a-provisioned-machine).

Experiments and destructive operations are separate from initial setup:

| Command (work example) | Effect |
|---|---|
| `bin/dev clone work risky-sdk-change` | Copy the primary into `work-exp-risky-sdk-change` |
| `bin/dev destroy-experiment work risky-sdk-change` | Delete that experiment |
| `bin/dev rebuild work` | Delete and recreate `work-dev` |
| `bin/dev destroy work` | Delete `work-dev` |

Use `--dry-run` to preview. Deletion requires the exact machine name unless
`--yes` is explicitly supplied. Clones copy private VM state too; follow the
[clone recovery guidance](docs/recovery.md#lost-experiment-machine) before use.

## Boundaries

- macOS: OrbStack, Tailscale, Remote Login, and independent Parallels on work.
- Ubuntu: active code under `~/code`, development tools, SDKs and AI CLIs.
- OrbStack Docker: shared image/cache storage with separate project data.
- MacBook Air: Zed, Ghostty, Tailscale and OpenSSH configuration.
- Secrets and user identities: private runtime state, never committed.

This provisioning checkout is the deliberate host-side exception: it must
exist on macOS before a VM can be created.

## Repository checks

The test Python needs `tomlkit` (installed by `python3-tomlkit` on the Ubuntu
workstations). On other systems, install it in a development virtual environment
and activate that environment before running the checks. Tests use temporary
homes and mock Claude's plugin installer; they do not modify real AI settings.

These checks do not provision a machine or start infrastructure:

```bash
make test
make lint
```

## Documentation

- [Step-by-step VM setup](docs/setup.md)

- [Architecture](docs/architecture.md)
- [Bootstrap and authentication](docs/bootstrap.md)
- [Docker and database helpers](docs/docker.md)
- [Optional Docker API access](docs/docker-api.md)
- [Local development TLS](docs/local-dev-tls.md)
- [Remote access, Zed, Ghostty and tmux](docs/remote-access.md)
- [Storage and external drive](docs/storage.md)
- [Recovery and rebuilds](docs/recovery.md)
- [Mac mini commissioning checklist](docs/commissioning.md)
