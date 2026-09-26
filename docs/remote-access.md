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

On the Air, with Tailscale connected and the destination mini/VM running:

1. Open Zed and press **Ctrl+Cmd+Shift+O** for **Remote Projects**.
2. Choose **Connect New Server** and enter `ssh personal-dev`.
3. Let Zed download/start its remote server. Choose a project directory such as
   `/home/LINUX_USER/code/project-a`, replacing the username and folder.
4. Repeat with `ssh work-dev` and the work project folder. If no repositories
   are cloned yet, open `~/code` temporarily rather than the whole home or `/`.
5. In each project's Zed terminal, run `hostname`, `pwd` and `command -v mise`.
   Confirm the matching VM, intended folder and managed tool environment.

Zed uses OpenSSH and the Air's existing jump-host configuration. Language
servers, tasks and terminals run in Ubuntu. Do not open the Mountain Duck
mount as a local Zed project when you intend to use the VM's development tools.
The Finder mounts are useful for transferring files independently of Zed.

If Zed cannot connect, first test `ssh personal-dev` or `ssh work-dev` in a local
Air terminal. If SSH works, inspect Zed's **Open Log** command and confirm the
VM can download its server. Do not replace working SSH keys as a first step.
If the terminal lacks tools, start a fresh login shell with `exec bash -l` and
rerun the VM verifier; an old terminal can predate bootstrap's PATH setup.

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
session. The tmux configuration advertises RGB colour, always reports extended
keys in CSI-u format to preserve shortcuts such as Shift+Enter, and allows
terminal escape-sequence passthrough so remote AI TUIs retain Ghostty's colour
and notification support. The managed `finish-dev` Bash alias runs
`tmux kill-session` to end the attached session when it is no longer needed.

The tmux server survives Air sleep, Wi-Fi changes and SSH disconnects while
the VM remains running. Reattach with the same command. VM restarts and
destruction end its sessions; important work must be committed and pushed.

## VM files in Finder on the Air

Mac-Bootstrap owns Mountain Duck installation and its two SFTP bookmarks; follow
[its Finder commissioning guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/mountain-duck.md).
Use the existing `work-dev` and `personal-dev` SSH routes, each with its own key,
to access the matching Linux home. No extra SMB server or client-side mount
software is installed by this repository. Keep active source under `~/code` in
Ubuntu and run builds and Git commands there. Finder mounts provide file access;
they do not redirect browser links launched by the guest to the Air.
