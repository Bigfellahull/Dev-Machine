# Repository guidance for coding agents

This repository provisions disposable development machines. Preserve these
invariants in every change:

- Never add secrets, tokens, private keys, real email addresses or passwords.
- Never install Docker Engine, Docker Desktop, Colima, Podman or another daemon
  inside the OrbStack Linux machine.
- Linux database administration must use OrbStack's supported `mac docker`
  bridge. Do not create or assume `/var/run/docker.sock`.
- Keep generic Ubuntu bootstrap logic under `bootstrap/`; keep OrbStack-specific
  lifecycle logic under `orb/`.
- Work and personal profiles share code but never credentials or runtime state.
- Destructive helpers must resolve one exact target and require confirmation.
- Do not use wildcard deletion or `orbctl delete --all`.
- Active code belongs in `~/code` inside Ubuntu, not on macOS mounts.
- Public documentation describes durable behavior and policy, not project
  status, implementation history, personal plans or acceptance progress.
- Run `make test` and `make lint` after changes.

For local infrastructure, start with `db --help`. For machine lifecycle, start
with `bin/dev --help`. Read `docs/architecture.md` before changing boundaries.
