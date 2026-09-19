# dev-machine

Reproducible Ubuntu development workstations hosted by OrbStack on separate
work and personal Mac minis. Repositories, SDKs, build tools and AI coding CLIs
live in Ubuntu; OrbStack's native Docker engine on macOS runs the databases.

## Start here

Follow this walkthrough independently on each mini. If the VM is already
provisioned, start at [step 2](#2-open-the-vm-and-check-provisioning).

| Profile | VM | Installed automatically |
|---|---|---|
| Both | — | .NET 10, Go, Node.js, Python, mise, Git/GitHub tools, shell tools, tmux, Codex, Claude, Grok and PostgreSQL helpers |
| Work | `work-dev` | Rust, Azure CLI, Azure Artifacts Credential Provider, SqlPackage, sqlcmd, WASM workload, PDF/media tools, pdfminer.six, Tesseract 5.5.2, SQL Server/Redis helpers and the Docker API tunnel helper |
| Personal | `personal-dev` | Railway CLI and the shared `use-railway` skill |

Provisioning installs tools. The checklist below covers your identity, logins,
certificates, database credentials and project configuration. Keep those
separate for work and personal, outside source control.

### 1. Create and provision the VM

**On the matching Mac mini, from this repository's root directory:**

- [ ] Follow the [Mac-Bootstrap commissioning guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/commissioning.md) through macOS installation, Remote Login, OrbStack and local CA setup (section 4, steps 1–3). Continue here to create the VM. Complete the remaining host and Air commissioning steps after the VM is ready. Confirm `docker compose version` works.
- [ ] Create the ignored host configuration if it does not already exist:

  ```bash
  mkdir -p config/local
  if [ ! -e config/local/host.env ]; then
    cp config/host.env.example config/local/host.env
  fi
  ```

- [ ] Edit `config/local/host.env` for the mini's resources. Defaults are 24 GB RAM and a 300 GB disk ceiling; the external drive setting is used only for backup/export operations.
- [ ] Preview and create the matching VM. Choose **one** pair of commands:

  **Work mini:**

  ```bash
  bin/dev create work --dry-run
  bin/dev create work
  ```

  **Personal mini:**

  ```bash
  bin/dev create personal --dry-run
  bin/dev create personal
  ```

`create` creates Ubuntu 26.04 ARM64, waits for cloud-init, runs bootstrap,
handles required Ubuntu reboots and seeds `~/code/dev-machine` inside Ubuntu.
Run host lifecycle commands as the normal macOS user. Bootstrap runs as the
normal Ubuntu development user and needs sudo inside the VM; it prompts when
cached or passwordless authorisation is unavailable. Internet access is needed
for Ubuntu packages and vendor downloads.

Use `bin/dev provision PROFILE` to finish or update an existing machine;
`create` refuses to replace it. Add `--skip-ai` to omit AI setup intentionally.

### 2. Open the VM and check provisioning

- [ ] **On the mini**, open the matching VM:

  ```bash
  orb -m work-dev
  ```

  Use `orb -m personal-dev` on the personal mini. A fresh shell loads the
  managed PATH, mise, Starship and shell integrations.

- [ ] **Inside Ubuntu**, check the profile and run the initial verification:

  ```bash
  cd ~/code/dev-machine
  cat ~/.config/dev-machine/profile
  bootstrap/verify.sh
  ```

  The marker should match the mini. Use `bootstrap/verify.sh --skip-ai` if you
  skipped AI setup. Fix failures before continuing. Warnings about GitHub,
  local TLS and the uncommissioned work Docker API tunnel are expected before
  completing the steps below.

All remaining commands run **inside Ubuntu**, except where marked otherwise.

### 3. Set up Git and AI access — both profiles

- [ ] Configure the identity for this profile and sign into GitHub. Replace the identity placeholders before running:

  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "private-address-for-this-profile"
  gh auth login
  gh auth status
  ```

  Configure Git authentication for your chosen HTTPS or SSH workflow. Confirm
  you can clone and fetch a private repository for this profile; CLI login
  alone does not prove that your chosen Git transport works.

- [ ] Open each AI CLI you use and complete its sign-in flow, unless AI setup was skipped:

  ```bash
  codex
  claude
  grok
  ```

  Exit each CLI before launching the next. Bootstrap manages the AI defaults,
  shared instructions and skills, and installs the three approved Claude plugins.
  Provider logins, project trust and MCP authentication remain private setup.
  Follow [AI configuration and MCP commissioning](docs/bootstrap.md#ai-tools):
  supply any private work MCP overrides; authenticate Railway and Linear on
  personal. Verify the relevant integrations in each AI client.

### 4. Set up local HTTPS — both profiles

- [ ] **On the matching mini**, create and export its profile-specific certificate handoff using the [Mac-Bootstrap TLS guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/local-dev-tls.md).
- [ ] Transfer the handoff into an exact temporary directory in the matching VM, then import it **inside Ubuntu**:

  ```bash
  local-dev-tls import /path/to/profile-matched-handoff
  local-dev-tls verify
  ```

- [ ] Remove the exact temporary handoff from both machines after verification. Trust only the profile's public root on browser clients, including the Air; the CA private key stays on its issuing mini.

### 5. Prepare projects and databases — both profiles

- [ ] Clone active repositories under `~/code` inside Ubuntu. Restore their local configuration and secrets from the appropriate private source.
- [ ] Configure each project's development wrapper to use the [shared TLS PEM or PFX paths](docs/local-dev-tls.md#project-wrappers).
- [ ] Follow each project's setup instructions to install its pinned runtimes and dependencies. Check exact .NET SDK pins in `global.json`; the moving global .NET 10 default does not guarantee a project's pinned SDK is installed.
- [ ] Create the private database configuration if needed:

  ```bash
  mkdir -p ~/.config/dev-machine
  if [ ! -e ~/.config/dev-machine/db.env ]; then
    cp ~/code/dev-machine/docker/db.env.example ~/.config/dev-machine/db.env
  fi
  chmod 600 ~/.config/dev-machine/db.env
  ```

- [ ] Edit that file before starting databases. Replace PostgreSQL's placeholder password on both profiles, plus SQL Server's and Redis's on work. Concurrent projects need separate `--env-file` files with distinct published ports.
- [ ] From the relevant **project directory**, start its required database and test the application connection:

  ```bash
  db --help
  db start postgres
  db status
  db connection postgres
  ```

  Use `--project NAME` to choose a different scope. Applications connect to
  `docker.orb.internal` and the configured published port. Database data lives
  in project-specific volumes on the matching Mac. See [database usage and
  isolation](docs/docker.md).

### 6. Complete the profile-specific setup

#### Work only

- [ ] Sign into Azure with `az login`, select the intended tenant/subscription and confirm it with `az account show`.
- [ ] In a project using private Azure Artifacts feeds, run `dotnet restore --interactive` and complete the work account flow. The credential provider is installed already.
- [ ] For projects using WASM, restore the required workload for the project's selected SDK; bootstrap's global workload does not cover every pinned SDK.
- [ ] Commission the [Docker API tunnel](docs/docker-api.md) using a unique VM key and a verified Mac host key. Run the project's Testcontainers suite or Aspire AppHost through `orbstack-docker-api run ...`, with its required Testcontainers settings and cleanup enabled.
- [ ] Start SQL Server and Redis with `db start mssql` and `db start redis` in projects that need them. Validate SQL Server's [unsupported ARM emulation](docs/docker.md#sql-server-on-apple-silicon) with representative workloads.
- [ ] Check `sqlpackage /Version` and test a representative BACPAC import/export before relying on SqlPackage on ARM64.
- [ ] For PDF/OCR projects, set `PDFMINER_PYTHON=/usr/bin/python3` in local project configuration and run their PDF, Tesseract 5.5.2 and media tests.

#### Personal only

- [ ] [Sign into Railway](https://docs.railway.com/cli/login) and confirm the account:

  ```bash
  railway login
  railway whoami
  ```

- [ ] Configure each Railway project's existing project, environment and service context before operating it. If the project uses a local link, inspect it with `railway status`. Keep credentials and local link state on personal.
- [ ] If AI setup was enabled, confirm `use-railway` is available to the AI CLIs. The [bootstrap guide](docs/bootstrap.md#ai-tools) describes its installation paths.

### 7. Connect from the Air and finish verification

- [ ] **On the Air and matching mini**, complete the [Mac-Bootstrap Air SSH guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/remote-access.md). It owns the aliases, separate keys and host trust; supply the actual Linux username from `whoami` inside each VM.
- [ ] **On the Air**, test `ssh work-dev` or `ssh personal-dev`, open a project in Zed using the same alias, and test Ghostty with `tmux new -As dev` inside Ubuntu. Disconnect and reattach. See [remote access](docs/remote-access.md).
- [ ] **Inside Ubuntu**, run each active project's restore/build/test workflow and check its database and HTTPS connections.
- [ ] Run the final machine verification:

  ```bash
  cd ~/code/dev-machine
  bootstrap/verify.sh
  ```

  Use `--skip-ai` if applicable. Require zero failures and resolve or explicitly
  account for every warning. Verification checks installed state and selected
  connections; it does not test every provider login or project workflow.

- [ ] Push important source changes and arrange project-specific database backups. On work, validate the [external storage and export workflow](docs/storage.md). A VM export supplements those backups.

For a new mini or a deliberate rebuild rehearsal, also run the broader
[commissioning and recovery checks](docs/commissioning.md).

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

- [Architecture](docs/architecture.md)
- [Bootstrap and authentication](docs/bootstrap.md)
- [Docker and database helpers](docs/docker.md)
- [Work Docker API access](docs/docker-api.md)
- [Local development TLS](docs/local-dev-tls.md)
- [Remote access, Zed, Ghostty and tmux](docs/remote-access.md)
- [Storage and external drive](docs/storage.md)
- [Recovery and rebuilds](docs/recovery.md)
- [Mac mini commissioning checklist](docs/commissioning.md)
