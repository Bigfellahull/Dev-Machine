# Bootstrap and authentication

For the provisioning commands and post-provision checklist, begin with the
[VM setup guide](setup.md). This guide explains what the
scripts manage and how updates work.

## Module order

`bootstrap/bootstrap.sh --profile work|personal` runs:

1. `base.sh` — curated Ubuntu packages and `~/code`.
2. `memory.sh` — 8 GB swap and resilient user-systemd OOM handling.
3. `dotnet.sh` — native Ubuntu dependencies required by Microsoft's .NET SDK.
4. `runtimes.sh` — latest mise and all profile-appropriate managed tools;
   adds SqlPackage, the .NET `wasm-tools` workload and Azure Artifacts Credential
   Provider on work, and Railway on personal.
5. `workstation-tools.sh` — common native libraries and database clients.
6. `work-tools.sh` — work-only native PDF/media packages, Azure CLI and sqlcmd.
7. `ocr.sh` — pinned work-only Tesseract runtime.
8. `ai-tools.sh` — official native Codex, Claude and Grok installers, shared
   skills and the personal-only Railway skill.
9. `shell.sh` — ble.sh installation through `blesh.sh`, PATH, mise activation,
   tmux, safe Git defaults and `db`.
10. `docker-bridge.sh` — OrbStack's supported macOS Docker command link and
    opt-in API tunnel service installation for either profile through `orb/docker-api.sh`.

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

The common mise configuration manages the latest Go, Node.js and
Python releases, age, bat, fd, fzf, Git LFS, GitHub CLI, ripgrep, ShellCheck,
sqlc, Starship and zoxide. Profile fragments select .NET SDKs and add tools
through mise's registry and `pipx:` backend. Tool declarations stay separate
because the global `config.toml` takes precedence over `conf.d` fragments.
This replaces separate `nvm`, `pyenv`, `asdf`, Go-manager
and standalone CLI update paths. A project `mise.toml`, `.nvmrc`, `.node-version`, `.python-version`,
`.go-version`, `global.json`, or Go toolchain directive can override the global
default where supported.

The global defaults deliberately move as new releases appear. Projects needing
stable or byte-for-byte tool selection should commit exact versions and a mise
lockfile. Provisioning upgrades moving global aliases and prunes the superseded
runtime versions without mise's default release-age delay. The official mise
installer also refreshes mise itself on every provisioning run. Save the
verification output in a private commissioning record when you need to know
which versions a rebuild selected; bootstrap does not maintain a version log.

mise's core .NET backend uses Microsoft's official install script and keeps the
global selection on the latest stable SDK in major version 10, independently of
the Ubuntu package release cadence. Ubuntu-packaged .NET files are removed to
prevent `/usr/bin/dotnet` from masking the managed SDK, while the required
Ubuntu native libraries remain apt-managed. The .NET backports PPA is not added.
ICU provides Unicode and locale-aware globalisation. LTTng-UST supports .NET's
Linux diagnostic and tracing pipeline; neither package installs another runtime
or background service.

The work profile preserves SDK `10.0.400` alongside the moving .NET 10 alias for
projects that request that exact SDK. It installs `wasm-tools` from workload
set `10.0.400.1` for that SDK. Workload installation and verification run from
`config/dotnet/work`, whose `global.json` selects `10.0.400` with roll-forward
disabled, independently of the caller's project. The verifier checks the selected
SDK and workload set without automatically installing missing SDKs. The explicit
mise version retains the build baseline alongside the moving alias.
Without a project `global.json`, .NET selects the highest installed SDK.
Personal machines retain the moving .NET 10 default without Wasm workloads.
Projects still control SDK selection through `global.json`; keep the work
build SDK and workload pins aligned when updating a supported project baseline.

Java is not installed.

Rust is declared in the work-only mise fragment and tracks the latest stable
toolchain. mise uses rustup underneath, so project Rust version files and the
normal Cargo layout continue to work without a separate bootstrap installer.
Personal machines do not install Rust.

Work additionally installs the native-build compiler in `config/rust-toolchain`
alongside that default. The verifier checks it explicitly. Work's cross-binutils
package provides `x86_64-w64-mingw32-objdump` for inspecting returned Windows x64
binaries on Ubuntu ARM64. Follow [Windows commissioning](windows-builds.md) to
install the corresponding pinned target in Parallels; Linux installation alone
does not configure Windows.

The work profile installs Microsoft's Azure Artifacts Credential Provider as a
global .NET tool from NuGet.org. Provisioning installs or updates to the latest
stable release without authenticating. Authentication remains runtime state;
the first restore for a private feed should use `dotnet restore --interactive`.
The personal profile removes the provider if it is present.

SqlPackage follows the same work-only .NET global-tool installation and update
policy, using Microsoft's `Microsoft.SqlPackage` package from NuGet.org.
`sqlpackage /Version` is part of verification. Microsoft's published Linux
support matrix lists x64; the ARM64 workstation also needs a representative
BACPAC import/export commissioning test before relying on it. See the
[SqlPackage installation guide](https://learn.microsoft.com/en-us/sql/tools/sqlpackage/sqlpackage-download).

The personal mise fragment installs the latest Railway CLI. Work removes that
managed tool and does not receive the Railway skill. Sign in with
`railway login` on personal after provisioning; authentication and project
links remain private runtime state.

## Workstation tools

The common apt profile installs libpq development files and Ubuntu's
PostgreSQL client. PostgreSQL is not installed as a Linux server. Common
standalone developer commands, including age, Git LFS and sqlc, come from mise.

Interactive Bash loads fzf's Ctrl-R history search, Ctrl-T file selection,
Alt-C directory navigation and fuzzy completion, and enables zoxide's `z` and
`zi` commands. Ctrl-T uses bat for syntax-highlighted file previews. Ubuntu's
`bash-completion` package provides command-specific tab completion.

Provisioning connects the managed environment to `.bashrc` and the first
readable Bash login file: `.bash_profile`, `.bash_login` or `.profile`. If none
exists, it creates `.profile`. Existing contents are preserved. Interactive
login shells, including OrbStack terminals, load mise and the managed PATH even
when their login file does not source `.bashrc`. Verification checks startup in
a fresh Bash login shell as well as checking the installed tools.

Both profiles install ble.sh from its upstream prebuilt nightly archive into
`~/.local/share/blesh`. Provisioning refreshes it on each run. Interactive Bash
loads it for inline autosuggestions and syntax highlighting, uses its fzf
compatibility modules, and attaches the line editor after Starship is configured.
Non-interactive shells do not load ble.sh. Personal ble.sh settings can go in
`~/.blerc`, which bootstrap leaves untouched.

To install or refresh just ble.sh and the shared shell integration, run these
commands inside Ubuntu from an up-to-date checkout:

```bash
cd ~/code/dev-machine
bash bootstrap/blesh.sh
source bootstrap/lib.sh
install_bash_startup
exec bash -l
```

The work profile additionally installs bzip2, FFmpeg, Ghostscript, Pandoc,
Poppler utilities, qpdf, Redis client tools and WeasyPrint's native Pango and
HarfBuzz libraries from Ubuntu. bzip2 supports extracting Microsoft's sqlcmd
release archive. The latest WeasyPrint CLI is isolated by mise's `pipx:` backend using mise-managed uv; the standalone
pipx package is not installed. Stable Rust and Syft are also work-only mise
tools.

Azure CLI comes from Microsoft's `resolute` ARM64 apt repository. The Go
implementation of sqlcmd uses a separate vendor installation path: bootstrap
downloads Microsoft's latest official ARM64 archive and verifies the
publisher's SHA-256 digest before installation. The AI
CLIs remain on their official native installers. After mise bootstraps itself,
ble.sh, the Azure Artifacts Credential Provider, SqlPackage, sqlcmd, pinned Tesseract
and the three AI CLIs are the non-apt, non-mise installation paths.

Work installs pdfminer.six through Ubuntu's `python3-pdfminer` package. Use
`PDFMINER_PYTHON=/usr/bin/python3` in the project's local configuration or
command wrapper so it uses that package rather than mise's separate Python.
The system package does not modify mise-managed or project Python environments.

Work builds Tesseract 5.5.2 from its checksum-verified official source archive
under `~/.local/share/dev-machine/tesseract`, using Ubuntu's CMake, Leptonica and
TIFF development packages. English and orientation language data come from Ubuntu.
Bootstrap removes Ubuntu's competing Tesseract executable so it cannot mask
the managed release. The pinned release supports OCR fixtures that require
5.5.2; it is not an assertion that output is identical across different language-data or native
library versions. Personal removes the managed OCR runtime and its work-only
packages. Verification checks the version, English language data and pdfminer
import. It also checks the FFmpeg encoders used by the work media pipeline.

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

Bootstrap manages selected fields in the AI configuration files on every run.
It uses Ubuntu's `python3-tomlkit` package to preserve TOML comments and unrelated
settings. JSON configuration is merged without replacing unrelated fields.
Configuration files are written atomically with mode `0600`; malformed files
and symlinked paths are rejected before any configuration is written. Close the
AI clients before provisioning so they cannot overwrite the updated settings.

| CLI | Model | Reasoning effort | Permission mode |
|---|---|---|---|
| Codex | `gpt-6-astra` | `high` | `on-request` with `auto_review` |
| Claude | `claude-fable-5-1` | `high` | `auto` |
| Grok | `grok-4.6` | `high` | `auto` |

These are global defaults, not restrictions on explicit command-line or project
overrides. Rerunning bootstrap restores the managed models, effort, permissions,
sandbox settings and named MCP registrations while preserving unrelated
configuration and authentication state. Conflicting Claude Fable 5.1 effort
overrides and Grok 4.6's legacy per-model effort setting are removed. No per-model
effort overrides are installed. Codex goals are enabled but no goal is created.

Codex retains its workspace-write sandbox and automatic approval reviewer.
Claude retains its enabled sandbox, refuses unsandboxed commands and fails when
the sandbox is unavailable. Grok uses `safe-workspace` with automatic Bash
approval disabled. Automated safety checks can still block actions or require
user input. Grok's `remember_mode` remains false so a temporary permission-mode
change does not become the default for later sessions. Its secondary fork model
is unset, so forks use the main default model. This does not change Grok's
separate conversational-memory settings.

### MCP servers and authentication

Bootstrap configures the following servers in Codex and Grok's user TOML files
and Claude's user-scoped `~/.claude.json`:

| Server | Work | Personal | Transport |
|---|---|---|---|
| Local work servers | Optional | No | Names and HTTPS endpoints supplied locally |
| Railway | No | Yes | `railway mcp` over stdio |
| Linear | No | Yes | `https://mcp.linear.app/mcp` |

Codex also retains the OpenAI documentation server. Work provisioning removes
the named Railway and Linear registrations. Personal provisioning does not read
the private work override. Other server registrations, account state and
unrelated plugins are preserved. This is not a way to convert a work VM into a
personal VM; use a fresh machine to keep credentials and runtime data separate.

To add private work servers, create an override in the checkout used to run
bootstrap. `config/local/` is ignored by Git:

```bash
mkdir -p config/local
if [ ! -e config/local/mcp.work.json ]; then
  install -m 0600 config/ai/mcp.work.example.json config/local/mcp.work.json
fi
```

Replace the example server name and URL with the private values. Each entry
maps a server name to an object containing only `url`; multiple servers are
allowed. Use HTTPS endpoints without tokens, query strings or embedded
credentials. Server names accept letters, digits, underscores and hyphens;
`railway`, `linear` and `openaiDeveloperDocs` are reserved. Authenticate through
each client's normal flow after provisioning.

For host-driven OrbStack provisioning, use the work mini's source checkout;
the initial VM checkout inherits that local file. For bootstrap run directly
inside Ubuntu, use its checkout. Keep the override on work machines and back it
up privately: Git clones do not include it. Then rerun provisioning or, inside
Ubuntu, update only the managed settings:

```bash
/usr/bin/python3 bootstrap/ai-config.py apply --profile work
```

The override is optional. When present, verification checks its registrations
in all three clients. When absent, work provisioning adds no private servers.
Private names and endpoints are never printed by the helper. Removing an
override entry does not delete an installed registration; remove it explicitly
from each client when retiring a service.

Complete each client's normal MCP authentication flow for private servers or Linear after
provisioning. Railway reuses the personal VM's `railway login` credentials; the
hosted proxy requires Railway CLI 5.44.0 or newer. Bootstrap does not sign in,
copy tokens, invoke MCP tools or add blanket permission rules for these servers.
Before changing any managed endpoint or stdio command, bootstrap checks the
original registration for authentication and other non-portable settings. This
includes environment-backed headers, credential helpers and unknown settings
that could carry credentials in newer clients. A conflict stops the operation
before any configuration file is written, without printing the private values.
Resolve the affected registration explicitly and retry. Unchanged destinations
keep their authentication; timeouts and tool restrictions survive endpoint
updates without credentials. The same checks apply to the documentation server.

See the [Railway MCP guide](https://docs.railway.com/ai/mcp-server),
[Linear MCP guide](https://linear.app/docs/mcp) and
[Claude user-scoped MCP configuration](https://code.claude.com/docs/en/mcp).

### Claude plugins

Both profiles install and enable these user-scoped plugins from Anthropic's
official `anthropics/claude-plugins-official` marketplace:

- `code-simplifier`
- `security-guidance`
- `code-review`

Bootstrap uses Claude's plugin installer only for missing or incomplete
installations. Verification checks the official marketplace source, user-scoped
registry entries, plugin manifests and enabled settings. An enabled setting
alone does not count as an installation. Other installed plugins are preserved.
Plugin install failures fail provisioning without printing captured CLI output.

Claude Code 2.1.257 or newer is required for Fable 5.1. If an existing CLI is too
old, run `claude update` and rerun provisioning. The bootstrap does not replace
existing CLI binaries simply to change configuration. See
[Claude model configuration](https://code.claude.com/docs/en/model-config) and
[plugin installation](https://code.claude.com/docs/en/discover-plugins).

### Instructions, skills and verification

Global AI instructions and the approved skill trees are managed on every run
unless `--skip-ai` is selected.
`codebase-sweep` and `collab` each have one canonical copy under
`~/.agents/skills`, with symlinks from `~/.claude/skills` and `~/.codex/skills`.
Grok discovers the shared location directly. Bootstrap moves an existing
Codex-owned `collab` directory to the shared location and updates its known
links; conflicting directories or unexpected links are left untouched and
reported as errors. The default `collab` panel is Claude, Grok,
and Codex, with whichever participating agent you are talking to as lead.
Each forms an independent position from a neutral brief before the panel
shares proposals and debates verified evidence. Shared instructions include
the writing and pasteable-output policy. No plugin registry, remembered
approval, project trust, hook, history or authentication state is copied
from another machine.

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

Personal additionally receives the complete vendored `use-railway` skill tree
under `~/.agents/skills`, with the same Claude and Codex symlink layout as the
shared skills. Work removes only recognised managed Railway skill copies;
unexpected or modified copies produce an error instead of being deleted.
`--skip-ai` skips Railway skill installation as well as the other AI setup;
the personal Railway CLI remains part of the runtime profile.

When provisioning intentionally uses `--skip-ai`, verify that configuration
with `bootstrap/verify.sh --skip-ai`.

The verifier checks managed settings and profile-specific MCP registrations
without authenticating or calling remote services. Test real MCP connections
after completing sign-in. Configuration and plugin checks can also be run
independently from the checkout:

```bash
/usr/bin/python3 bootstrap/ai-config.py verify --profile work
/usr/bin/python3 bootstrap/ai-config.py verify-plugins --profile work
```

Use `personal` on the personal VM. The configuration helper defaults to the
Ubuntu system Python, where the apt-managed TOML dependency is installed.
`DEV_MACHINE_PYTHON` is an override for isolated test environments.

OpenAI documents its standalone Linux installation in the
[official Codex CLI documentation](https://learn.chatgpt.com/docs/codex/cli).

## Git and GitHub identity

Provisioning sets only non-identity Git behaviour. Configure identity privately:

```bash
git config --global user.name "Your Name"
git config --global user.email "private-address-for-this-host"
gh auth login
gh auth status
```

Do this independently on work and personal. SSH private keys, agent state and
GitHub tokens are runtime state, not repository content.

The managed behaviour uses `main` for new repositories, prunes deleted remote
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

On the matching Mac mini, review and update the host checkout, then run from
its root directory:

```bash
bin/dev provision work --dry-run
bin/dev provision work
```

Use `personal` on the personal mini. This path handles required Ubuntu reboots.
It leaves an existing `~/code/dev-machine` Git checkout unchanged. Inside Ubuntu,
review and update that checkout separately to the same revision, preserving any
local changes, then open a fresh shell and run:

```bash
cd ~/code/dev-machine
bootstrap/verify.sh
```

Pass `--skip-ai` to both provisioning and verification when appropriate. A stale
guest checkout can compare installed files against old definitions.

For direct provisioning inside Ubuntu, run
`bootstrap/bootstrap.sh --profile work` from its checkout. This also upgrades
packages, but does not restart the VM. If `/var/run/reboot-required` exists,
restart the matching VM before verification.

Keep a VM on its intended profile. Package removal on a profile change does not
erase credentials or turn an existing VM into a clean work/personal boundary.
A clean rebuild remains the stronger acceptance test for undocumented state.
