# Bootstrap and authentication

## Module order

`bootstrap/bootstrap.sh --profile work|personal` runs:

1. `base.sh` — curated Ubuntu packages and `~/code`.
2. `memory.sh` — 8 GB swap and resilient user-systemd OOM handling.
3. `dotnet.sh` — native Ubuntu dependencies required by Microsoft's .NET SDK.
4. `runtimes.sh` — latest mise and all profile-appropriate managed tools;
   adds the .NET `wasm-tools` workload and Azure Artifacts Credential Provider
   on work machines.
5. `workstation-tools.sh` — common native libraries and database clients.
6. `work-tools.sh` — work-only native PDF/media packages, Azure CLI and sqlcmd.
7. `ai-tools.sh` — official native Codex, Claude and Grok installers.
8. `shell.sh` — PATH, mise activation, tmux, safe Git defaults and `db`.
9. `docker-bridge.sh` — OrbStack's supported macOS Docker command link.

Every module ensures state and can be rerun. Apt installs, managed files, Git
includes and shell source lines are idempotent. Rerunning also removes managed
packages, mise tools and commands that do not belong to the selected profile.

`shell.sh` installs the `local-dev-tls` importer, but bootstrap does not run it.
The matching Mac-generated handoff contains a private leaf key and importing its
public CA changes Ubuntu trust, so that remains an explicit commissioning step.

## Memory resilience

The common bootstrap creates an 8 GB `/swapfile` only when the machine has no
active swap. A valid existing swap configuration is preserved. The swap file
uses virtual-disk space rather than guest or host RAM and is persisted in
`/etc/fstab`.

The bootstrap also installs `DefaultOOMPolicy=continue` for the user systemd
manager. If the kernel kills a memory-heavy build subprocess, systemd leaves
the other processes in its transient scope running. This preserves the tmux
pane and AI CLI session, but the affected build still fails normally.

## Installation strategy

There are two primary managers. Apt owns the Ubuntu base, native libraries,
database clients and applications that integrate with the distribution. mise
owns versioned development runtimes and standalone CLIs. The bootstrap does not
also install a mise-owned command with apt, pipx, `go install`, rustup or an
additional vendor repository.

The common mise configuration manages .NET 10, the latest Go, Node.js and
Python releases, age, bat, fd, fzf, Git LFS, GitHub CLI, ripgrep, ShellCheck,
sqlc, Starship and zoxide. It uses maintained core and Aqua backends and
replaces separate `nvm`, `pyenv`, `asdf`, Go-manager and standalone CLI update
paths. A project `mise.toml`, `.nvmrc`, `.node-version`, `.python-version`,
`.go-version`, `global.json`, or Go toolchain directive can override the global
default where supported.

The global defaults deliberately move as new releases appear. Projects needing
stable or byte-for-byte tool selection should commit exact versions and a mise
lockfile. Provisioning upgrades moving global aliases and prunes the superseded
runtime versions without mise's default release-age delay. The official mise
installer also refreshes mise itself on every provisioning run. A clean rebuild
records which versions those aliases resolved to.

mise's core .NET backend uses Microsoft's official install script and keeps the
global selection on the latest stable SDK in major version 10, independently of
the Ubuntu package release cadence. Ubuntu-packaged .NET files are removed to
prevent `/usr/bin/dotnet` from masking the managed SDK, while the required
Ubuntu native libraries remain apt-managed. The .NET backports PPA is not added.
ICU provides Unicode and locale-aware globalization. LTTng-UST supports .NET's
Linux diagnostic and tracing pipeline; neither package installs another runtime
or background service.

The `wasm-tools` workload is installed only when the work profile is selected.
Projects control SDK selection through `global.json`; an exact SDK version
with `rollForward: disable` must exist or be updated before that project builds.

Java is not installed.

Rust is declared in the work-only mise fragment and tracks the latest stable
toolchain. mise uses rustup underneath, so project Rust version files and the
normal Cargo layout continue to work without a separate bootstrap installer.
Personal machines do not install Rust.

The work profile installs Microsoft's Azure Artifacts Credential Provider as a
global .NET tool from NuGet.org. Provisioning installs or updates to the latest
stable release without authenticating. Authentication remains runtime state;
the first restore for a private feed should use `dotnet restore --interactive`.
The personal profile removes the provider if it is present.

## Workstation tools

The common apt profile installs libpq development files and Ubuntu's
PostgreSQL client. PostgreSQL is not installed as a Linux server. Common
standalone developer commands, including age, Git LFS and sqlc, come from mise.

Interactive Bash loads fzf's Ctrl-R history search, Ctrl-T file selection,
Alt-C directory navigation and fuzzy completion, and enables zoxide's `z` and
`zi` commands. Ctrl-T uses bat for syntax-highlighted file previews. Ubuntu's
`bash-completion` package provides command-specific tab completion.

The work profile additionally installs bzip2, FFmpeg, Ghostscript, Pandoc,
Poppler utilities, qpdf, Redis client tools and WeasyPrint's native Pango and
HarfBuzz libraries from Ubuntu. bzip2 supports extracting Microsoft's sqlcmd
release archive; no active project invokes it directly. The latest WeasyPrint
CLI is isolated by mise's `pipx:` backend using mise-managed uv; the standalone
pipx package is not installed. Stable Rust and Syft are also work-only mise
tools.

Azure CLI remains in Microsoft's supported Ubuntu 26.04 ARM64 apt repository:
its GitHub releases do not publish a Linux ARM64 executable for mise to manage.
The Go implementation of sqlcmd remains a checked exception because it is not
in mise's registry; the bootstrap downloads Microsoft's latest official ARM64
archive and verifies the publisher's SHA-256 digest before installation. The AI
CLIs remain on their official native installers. After mise bootstraps itself,
the Azure Artifacts Credential Provider, sqlcmd and the three AI CLIs are the
only non-apt, non-mise installation paths.

7-Zip, standalone pipx, rclone, Buf, AWS CLI, Colima, Caddy, Certbot,
Cloudflared, mkcert, libgdiplus and SDL development libraries are outside the
managed workstation profiles. Project-specific tools belong in project
configuration rather than the machine bootstrap.

The local development TLS importer deliberately uses OpenSSL from Ubuntu and
does not install `mkcert`. Issuance and CA private-key custody remain on the
matching Mac mini.

Common dependencies are shared by both profiles. Profile-specific dependencies
are enabled only by the applicable profile, and project-specific dependencies
stay with the project.

The common database runtime contains only PostgreSQL. The work profile also
installs Redis and SQL Server Compose definitions and the corresponding client
tools. Containers run in OrbStack's macOS Docker engine rather than
inside Ubuntu.

## AI tools

The three AI CLIs use their vendors' native installers. They install capability
reproducibly but track each vendor's stable release channel rather than a
permanent binary checksum. Existing installs are not replaced on every
bootstrap run. Record versions in a commissioning log and update them
deliberately when validating a rebuild.

Bootstrap installs safe model, approval and sandbox defaults from `config/ai/`.
Each file is created only when absent so reruns preserve user changes,
plugins and MCP configuration. The files contain no authentication state;
credentials remain separate for every machine and profile.

Global AI instructions and the approved skill trees are managed on every run.
`codebase-sweep` and `collab` each have one canonical copy under
`~/.agents/skills`, with symlinks from `~/.claude/skills` and `~/.codex/skills`.
Grok discovers the shared location directly. Bootstrap moves an existing
Codex-owned `collab` directory to the shared location and updates its known
links; conflicting directories or unexpected links are left untouched and
reported as errors. The default `collab` panel is Claude, Grok,
and Codex, with whichever participating agent you are talking to as lead.
Each forms an independent position from a neutral brief before the panel
shares proposals and debates verified evidence. No plugin registry,
remembered approval, project trust, hook, history or authentication state
is copied.

Claude follows the terminal appearance automatically, Grok minimal mode uses
the terminal palette, and Codex leaves its independent syntax-highlighting
theme unset. Codex and Grok filter common secret-shaped environment variable
names before launching tool subprocesses.

No login is attempted during bootstrap. After provisioning, run each command and
complete its normal browser/device flow:

```bash
codex
claude
grok
```

When provisioning intentionally uses `--skip-ai`, verify that configuration
with `bootstrap/verify.sh --skip-ai`.

OpenAI documents its standalone Linux installation in the
[official Codex CLI documentation](https://learn.chatgpt.com/docs/codex/cli).

## Git and GitHub identity

Provisioning sets only non-identity Git behavior. Configure identity privately:

```bash
git config --global user.name "Your Name"
git config --global user.email "private-address-for-this-host"
gh auth login
gh auth status
```

Do this independently on work and personal. SSH private keys, agent state and
GitHub tokens are runtime state, not repository content.

The managed behavior uses `main` for new repositories, prunes deleted remote
branches, creates an upstream on the first push, follows annotated tags, rebases
on pull and reuses recorded conflict resolutions. `git lfs install --skip-repo`
configures global LFS filters without changing any repository.

## Ubuntu updates

Cloud-init refreshes package metadata and upgrades the base Ubuntu image before
bootstrap begins, and `base.sh` repeats the upgrade on later provisioning runs.
Automatic reboot is disabled inside cloud-init so the OrbStack lifecycle can
detect `/var/run/reboot-required`, restart the exact machine and wait for it
before continuing or returning control.

## Updating a provisioned machine

Pull this repository, review the diff, and rerun:

```bash
bootstrap/bootstrap.sh --profile work
bootstrap/verify.sh
```

Use `personal` on that host. A clean rebuild remains the stronger acceptance
test because it detects undocumented state.
