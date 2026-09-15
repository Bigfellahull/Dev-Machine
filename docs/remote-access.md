# Remote access, Zed, Ghostty and tmux

## SSH ownership and commissioning

`mac-bootstrap` owns the Air OpenSSH aliases, Tailscale jump-host routing and
macOS access commissioning. Follow its
[Air SSH access guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/remote-access.md)
to configure `work-mini`, `work-dev`, `personal-mini` and `personal-dev`,
authorise separate work/personal Air keys, and verify host fingerprints.

Use the same aliases on the LAN and away. They connect through each mini over
Tailscale to its loopback OrbStack SSH endpoint. The Air does not need a local
OrbStack installation. No Air SSH configuration is installed by `dev-machine`.

This repository owns the destination Ubuntu machines and their Linux users.
Supply those usernames to the Air settings in `mac-bootstrap`; keep account
identities and credentials outside both repositories. Provision and start the
matching `work-dev` or `personal-dev` machine before testing remote access.

After macOS access commissioning, test each provisioned destination from the Air:

```bash
ssh work-dev
ssh personal-dev
```

## Zed

Zed shells out to OpenSSH and reads `~/.ssh/config`, including jump-host
settings. In Remote Projects, connect using:

```text
ssh work-dev
```

and open a specific directory such as `~/code/project-a`, not `/` or an enormous
home directory. Language servers, tasks and terminals then run in Ubuntu. Zed
supports ARM64 Linux remote servers and SSH `-J`/ProxyJump.

See [Zed remote development](https://zed.dev/docs/remote-development).

Browser access to VM development servers also needs routing and certificate
trust. Follow [browsing from the Air](local-dev-tls.md#browsing-from-the-air)
for a local SSH port forward.

## Ghostty and tmux

Ghostty runs locally. Normal `ssh work-dev` uses the same OpenSSH alias. The Air
profile in `mac-bootstrap` enables Ghostty's SSH environment and terminfo
handling.

Inside Ubuntu:

```bash
tmux new -As dev
```

Interactive Bash shells use the same managed Starship prompt as the Air's zsh
session. The tmux configuration advertises RGB colour and extended keys and
allows terminal escape-sequence passthrough so remote AI TUIs retain Ghostty's
colour and notification support. The managed `finish-dev` Bash alias runs
`tmux kill-session` to end the attached session when it is no longer needed.

The tmux server survives Air sleep, Wi-Fi changes and SSH disconnects while
the VM remains running. Reattach with the same command. VM restarts and
destruction end its sessions; important work must be committed and pushed.
