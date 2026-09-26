# Create and commission a development VM

Follow this walkthrough independently on each mini. If the VM is already
provisioned, start at [step 2](#2-open-the-vm-and-check-provisioning).
For a complete new Air-and-minis installation, use the
[Mac-Bootstrap end-to-end guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/setup.md)
as the main route. This page covers the Ubuntu portion independently.

| Profile | VM | Installed automatically |
|---|---|---|
| Both | — | .NET 10, Go, Node.js, Python, mise, Git/GitHub tools, shell tools, tmux, Codex, Claude, Grok and PostgreSQL helpers |
| Work | `work-dev` | Rust, Azure CLI, Azure Artifacts Credential Provider, SqlPackage, sqlcmd, WASM workload, PDF/media tools, pdfminer.six, Tesseract 5.5.2, SQL Server/Redis helpers |
| Personal | `personal-dev` | Railway CLI and the shared `use-railway` skill |

Provisioning installs tools. The checklist below covers your identity, logins,
certificates, database credentials and project configuration. Keep those
separate for work and personal, outside source control.

## 1. Create and provision the VM

**On the matching Mac mini:** obtain this repository if it is not present, then work from its root. An existing checkout or extracted archive can be used instead of cloning over it.

```bash
mkdir -p ~/Downloads
cd ~/Downloads
git clone https://github.com/Bigfellahull/Dev-Machine.git
cd Dev-Machine
```

- [ ] Complete steps 1–3 of the [Mac-Bootstrap end-to-end guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/setup.md): Mac applications, Tailscale, Remote Login and OrbStack. Confirm `docker compose version` works. No Ubuntu commands run on macOS.
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

## 2. Open the VM and check provisioning

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
  local TLS and the uncommissioned opted-in Docker API tunnel are expected before
  completing the steps below.

All remaining commands run **inside Ubuntu**, except where marked otherwise.
The seeded `~/code/dev-machine` may be a copied snapshot or a Git checkout,
depending on the mini source. Check `git -C ~/code/dev-machine status` before
assuming it can be pulled or committed. A separately cloned `~/code/Dev-Machine`
is a different path on Linux; use the intended checkout consistently.

## 3. Set up Git and AI access — both profiles

- [ ] Configure the identity for this profile and sign into GitHub. Replace the identity placeholders before running:

  ```bash
  git config --global user.name "Your Name"
  git config --global user.email "private-address-for-this-profile"
  gh auth login
  gh auth status
  ```

  For SSH repository URLs, install/create a separate Git-provider key inside
  this VM and authorise its public key with the provider. The Air access key
  does not give the VM GitHub access. Configure Git authentication for your chosen HTTPS or SSH workflow. Confirm
  you can clone and fetch a private repository for this profile; CLI login
  alone does not prove that your chosen Git transport works.

- [ ] Open each AI CLI you use and complete its sign-in flow, unless AI setup was skipped:

  ```bash
  codex
  claude
  grok
  ```

  Exit each CLI before launching the next. A link launched by the guest normally
  opens on the mini. Use the provider's supported remote/device login flow or
  copy the displayed URL to the Air; localhost callbacks may require a forward. Bootstrap manages the AI defaults,
  shared instructions and skills, and installs the three approved Claude plugins.
  Provider logins, project trust and MCP authentication remain private setup.
  Follow [AI configuration and MCP commissioning](bootstrap.md#ai-tools):
  supply any private work MCP overrides; authenticate Railway and Linear on
  personal. Verify the relevant integrations in each AI client.

## 4. Set up local HTTPS — both profiles

- [ ] **On the matching mini**, create and export its profile-specific certificate handoff using steps 5–6 of the [end-to-end guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/setup.md#5-issue-and-transfer-the-matching-https-certificate), which include the transfer commands and cleanup. If you already completed those steps, verify the installed material instead of importing it again.
- [ ] Transfer the handoff into an exact temporary directory in the matching VM, then import it **inside Ubuntu**:

  ```bash
  local-dev-tls import /path/to/profile-matched-handoff
  local-dev-tls verify
  ```

- [ ] Remove the exact temporary handoff from both machines after verification. Trust only the profile's public root on browser clients, including the Air; the CA private key stays on its issuing mini.

## 5. Prepare projects and databases — both profiles

- [ ] Clone active repositories under `~/code` inside Ubuntu using their actual URLs:

  ```bash
  mkdir -p ~/code
  cd ~/code
  git clone REPOSITORY_URL project-a
  cd project-a
  git fetch
  ```

  Restore local configuration and secrets from the appropriate private source.
  If these are not available, defer project launch; the editor and VM checks can
  still be completed. Do not put project secrets in either bootstrap repository.
- [ ] Configure each project's development wrapper to use the [shared TLS PEM or PFX paths](local-dev-tls.md#project-wrappers).
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

  Use `--project NAME` to choose a different scope. The helper prints `docker.orb.internal` and the configured published port;
  verify that endpoint from Ubuntu. For loopback-published ports that refuse
  that route, test `host.orb.internal` as described in the
  [networking checks](docker.md#check-the-database-endpoint). Database data lives
  in project-specific volumes on the matching Mac. See [database usage and
  isolation](docker.md).

## 6. Complete the profile-specific setup

- [ ] **Optional on either profile:** opt in and commission the [Docker API tunnel](docker-api.md) using a unique VM key and a verified Mac host key. The [end-to-end guide, step 7](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/setup.md#7-opt-into-the-docker-api-bridge-if-needed) shows the host/guest order. Run the project's Testcontainers suite or Aspire AppHost through `orbstack-docker-api run ...`, with its required Testcontainers settings and cleanup enabled.

### Work only

- [ ] **Deferrable until a Windows build is needed:** complete [Windows native build commissioning](windows-builds.md) after creating or restoring the Parallels Windows VM. Run `orbstack-windows-build provision` and `orbstack-windows-build verify` inside Ubuntu before a project needs Windows native compilation.

- [ ] Sign into Azure with `az login`, select the intended tenant/subscription and confirm it with `az account show`.
- [ ] In a project using private Azure Artifacts feeds, run `dotnet restore --interactive` and complete the work account flow. The credential provider is installed already.
- [ ] For projects using WASM, restore the required workload for the project's selected SDK; bootstrap's global workload does not cover every pinned SDK.
- [ ] Start SQL Server and Redis with `db start mssql` and `db start redis` in projects that need them. Validate SQL Server's [unsupported ARM emulation](docker.md#sql-server-on-apple-silicon) with representative workloads.
- [ ] Check `sqlpackage /Version` and test a representative BACPAC import/export before relying on SqlPackage on ARM64.
- [ ] For PDF/OCR projects, set `PDFMINER_PYTHON=/usr/bin/python3` in local project configuration and run their PDF, Tesseract 5.5.2 and media tests.

### Personal only

- [ ] [Sign into Railway](https://docs.railway.com/cli/login) and confirm the account:

  ```bash
  railway login
  railway whoami
  ```

- [ ] Configure each Railway project's existing project, environment and service context before operating it. If the project uses a local link, inspect it with `railway status`. Keep credentials and local link state on personal.
- [ ] If AI setup was enabled, confirm `use-railway` is available to the AI CLIs. The [bootstrap guide](bootstrap.md#ai-tools) describes its installation paths.

## 7. Connect from the Air and finish verification

- [ ] **On the Air and matching mini**, complete the [Mac-Bootstrap Air SSH guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/remote-access.md). It owns the aliases, separate keys and host trust; supply the actual Linux username from `whoami` inside each VM.
- [ ] **On the Air**, test `ssh work-dev` or `ssh personal-dev`, open a project in Zed using the same alias, and test Ghostty with `tmux new -As dev` inside Ubuntu. Disconnect and reattach. Follow the [Zed click-by-click steps](remote-access.md#zed). For Finder file transfers, connect the Mountain Duck bookmarks installed on the Air; use Zed remote projects for development.
- [ ] **Inside Ubuntu**, run each active project's restore/build/test workflow and check its database and HTTPS connections.
- [ ] Run the final machine verification:

  ```bash
  cd ~/code/dev-machine
  bootstrap/verify.sh
  ```

  Use `--skip-ai` if applicable. Require zero failures and resolve or explicitly
  account for every warning. Verification checks installed state and selected
  connections; it does not test every provider login or project workflow.

- [ ] Push important source changes and arrange project-specific database backups. On work, validate the [external storage and export workflow](storage.md). A VM export supplements those backups.

For a new mini or a deliberate rebuild rehearsal, also run the broader
[commissioning and recovery checks](commissioning.md).
