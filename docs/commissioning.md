# Mac mini commissioning checklist

Start with the [README setup walkthrough](../README.md#start-here) for script
commands, logins and the post-provision checklist. Use this guide for broader
acceptance checks on a new mini or a deliberate rebuild rehearsal.

Run work and personal commissioning independently. Keep their local
configuration, keys, tokens and database state separate. Record versions and
results privately, outside the repository.

## Host

Run host commands on the matching Mac mini.

- [ ] Complete the matching Mac-Bootstrap profile, including macOS updates, stable hostnames, OrbStack, Tailscale and Remote Login for the intended account.
- [ ] Run `orbctl version`, `orbctl doctor`, `docker context show` and `docker compose version`.
- [ ] Review resource ceilings in ignored `config/local/host.env` before creating the VM.
- [ ] On work, validate Parallels independently of OrbStack and this repository.

## Primary machine

After completing the README checklist, run these checks inside Ubuntu.

- [ ] Confirm Ubuntu 26.04 and ARM64, and the correct `~/.config/dev-machine/profile` marker.
- [ ] Run `bootstrap/verify.sh` with zero failures. Use `--skip-ai` only when AI setup was intentionally skipped. Resolve or account for each warning; warnings do not cause a non-zero exit status.
- [ ] Confirm `swapon --show` reports active swap and `systemctl --user show -p DefaultOOMPolicy` reports `continue`.
- [ ] Confirm authenticated Git access and the AI provider logins you use.
- [ ] Build and test representative projects for each ecosystem used on this profile, from `~/code`. Check project-pinned SDKs and workloads as well as global defaults.
- [ ] Validate shared TLS with the development servers those projects use, including browsers on the mini and Air. Check the SSH port forward when browsing a VM service from the Air.
- [ ] Confirm browser clients trust the required public roots and no CA private key left its issuing mini. Remove temporary certificate handoffs after successful import.

### Work

- [ ] Verify Azure account selection and a private-feed restore using the installed Azure Artifacts Credential Provider.
- [ ] Commission the [Docker API tunnel](docker-api.md). Run a representative Testcontainers suite and, where used, an Aspire AppHost through the wrapper with the project's additional settings and resource cleanup enabled.
- [ ] Test SqlPackage BACPAC import/export on ARM64; a successful version check alone does not validate that workflow.
- [ ] Exercise Rust and PDF/media projects. Confirm `PDFMINER_PYTHON=/usr/bin/python3` where required and run OCR fixtures with Tesseract 5.5.2. Record language-data and native-library versions if results differ.
- [ ] Confirm Railway and its managed skill are absent.

### Personal

- [ ] Confirm the Railway login, intended project context and availability of `use-railway` when AI setup is enabled.
- [ ] Confirm the verifier reports work-only tools and runtime state absent, including Rust, PDF/media tools, Azure CLI, credential provider, SqlPackage, Tesseract and the Docker API service.
- [ ] Confirm `db --help` lists only PostgreSQL and rejects SQL Server and Redis.

## Infrastructure

Run database commands inside Ubuntu, using explicit test project scopes and
private environment files. Use distinct published ports for concurrent scopes.

- [ ] Start PostgreSQL and test it from Ubuntu through `docker.orb.internal`.
- [ ] On work, test Redis and SQL Server. Record SQL Server's emulation performance and representative schema/backup/restore results, including its unsupported-emulation limitation.
- [ ] Confirm project B receives different containers and volumes from project A.
- [ ] Using disposable database data only, confirm resetting one exact project/engine leaves the other scope intact.

## Remote client

- [ ] Complete the [Mac-Bootstrap Air SSH access guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/remote-access.md), including distinct work/personal keys and verified host fingerprints.
- [ ] Confirm the Air settings name the actual Linux user in each matching VM.
- [ ] Test `ssh work-dev` and `ssh personal-dev` on the LAN and away through Tailscale, for each provisioned destination.
- [ ] Open a project through Zed using the same alias.
- [ ] Start a Ghostty SSH session and `tmux new -As dev`; disconnect and reattach.
- [ ] Check prompt symbols and AI terminal colours inside and outside tmux.

## Storage and recovery

- [ ] Back up and restore representative PostgreSQL data, plus SQL Server data on work.
- [ ] On work, prepare the [external storage layout](storage.md), disconnect the drive and verify the VM remains usable.
- [ ] Confirm export fails while the drive is absent and succeeds after it is reconnected. Keep the archive and manifest together with restricted access.
- [ ] Repeat provisioning through `bin/dev provision PROFILE` on the mini, then run verification from the matching revision inside Ubuntu. Confirm private configuration and authentication remain usable.

## Destructive acceptance test

Run this only after important source and database state is recoverable elsewhere.
On the matching Mac mini, from the host checkout, preview the exact target:

```bash
bin/dev rebuild work --dry-run
bin/dev rebuild work
```

Use `personal` on the personal mini. Complete the [README checklist](../README.md#2-open-the-vm-and-check-provisioning)
again, including authentication, TLS import and the work tunnel's new key.
Repeat representative project, infrastructure and remote-client checks. A
successful clean rebuild validates the documented setup for those workflows.
