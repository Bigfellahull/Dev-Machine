# Architecture

## Deployment shape

```text
MacBook Air
  Zed / Ghostty / Tailscale / OpenSSH
              |
              v
work-mini or personal-mini
  macOS / Tailscale / Remote Login
  OrbStack
    primary Ubuntu machine: work-dev or personal-dev
    disposable clones:      work-exp-* or personal-exp-*
    native Docker:          profile- and project-scoped databases
  Parallels on work only (independent)
```

Work and personal minis have no runtime dependency on one another. The same
repository code may be used on both, but local configuration, keys, tokens,
database data and identities are separate.

The Ubuntu machines own the shared Starship prompt and AI CLI instructions and
skills. Ghostty remains on the Air and supplies terminal rendering over SSH.
`mac-bootstrap` owns the Air SSH aliases, Tailscale routing and macOS access
commissioning. This repository owns the destination machine names and Linux
users, and consumes those client aliases in its remote workflow.

## State boundaries

| State | Location | Authority |
|---|---|---|
| Source code | Remote Git repositories | Authoritative |
| Machine definition | This repository | Authoritative |
| Important DB state | Explicit dumps/backups | Authoritative when required |
| Docker volumes | OrbStack Docker on internal SSD | Working state |
| Ubuntu machine | OrbStack on internal SSD | Disposable working state |
| Machine exports | External SSD | Convenience recovery artifact |
| Local CA private key | Matching Mac mini only | Durable issuer state |
| Leaf certificate, key and PFX | Matching Ubuntu profile | Rebuildable commissioned state |

The provisioning repository is a small, deliberate exception to the rule that
repositories live in Ubuntu: lifecycle scripts must be available on macOS before
Ubuntu exists. Provisioning mirrors that checkout to `~/code/dev-machine` after
bootstrap so it is also available in the workstation. No project toolchain is
required on the host to run the lifecycle scripts.

## Layering

```text
orb/ lifecycle + cloud-init
              |
              v
generic Ubuntu 26.04 ARM64
              |
              v
bootstrap/ modules + work/personal profile
```

`bootstrap/` does not require OrbStack except for the optional Docker command
bridge module. Another Ubuntu provider can reuse the rest of the bootstrap.
The bridge delegates work-only Docker API service installation to `orb/`.
Its dedicated SSH key and verified Mac host key are commissioned inside each
work VM. Applications opt into the forwarded API per command; database
administration continues to use `mac docker`.

Local development TLS follows the same provider-neutral boundary. The Mac
issuer exports a profile-marked handoff; Ubuntu imports the public root and leaf
material without installing `mkcert`. Project wrappers consume stable PEM or
PFX paths without owning trust establishment.

Cloud-init upgrades the Ubuntu base and installs only a stable minimum. The
OrbStack lifecycle checks for required reboots both before and after bootstrap. Frequently
changing tools remain in normal scripts so they can be rerun and tested
independently.

## Resource defaults

The default ceiling is 24 GB RAM and 300 GB disk for a primary machine, leaving
capacity for macOS and other host workloads. Override memory in ignored
`config/local/host.env` to suit the host. CPU is unset by default so OrbStack's
global scheduling remains dynamic. Bootstrap creates an 8 GB swap file inside
the virtual disk when no active swap exists; it preserves an existing active
swap configuration. Swap does not reduce the machine's RAM ceiling or reserve
host memory.

Clones inherit the safe disk ceiling and copy data on demand; their memory limit
is reduced to 8 GB. Do not reduce a clone's disk ceiling blindly because its
source may already contain more data than the new limit.

The user systemd manager defaults to `OOMPolicy=continue`, so an OOM kill of a
build subprocess does not cause systemd to terminate the remaining processes in
the same tmux scope.

## OrbStack requirements

The lifecycle scripts target `ubuntu:resolute` on ARM64 and require cloud-init,
resource flags, cloning and host command bridging. Check the installed
OrbStack version and these capabilities during [commissioning](commissioning.md).

OrbStack's [SSH service](https://docs.orbstack.dev/machines/ssh) listens only on
localhost, so remote access uses the mini as a jump host. Docker-published
ports are reachable from Linux at `docker.orb.internal`.

Personal machines receive only the PostgreSQL Compose definition. Work
machines additionally receive Redis and SQL Server definitions. The shared
repository retains all definitions, while the managed runtime copy inside each
Ubuntu machine contains only that profile's enabled engines.
