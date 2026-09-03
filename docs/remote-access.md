# Remote access, Zed, Ghostty and tmux

## Recommended network path

Install Tailscale on the Air and each mini, not inside every Ubuntu machine.
Enable MagicDNS and give the minis stable names `work-mini` and
`personal-mini`. Use ordinary macOS Remote Login over the Tailscale network;
public Internet port forwarding is unnecessary.

Using the MagicDNS name all the time is the simplest LAN/remote policy. Tailscale
can establish a direct peer-to-peer path when both devices are local, while the
logical SSH target stays unchanged when the Air moves networks.

OrbStack's multiplexed SSH server listens only on the mini's localhost port
32222. OpenSSH `ProxyJump` first logs into the mini and then reaches that local
endpoint. This is supported behavior, not a public OrbStack SSH listener.

## Keys and authorization

Create distinct Air keys for work and personal. Authorize the corresponding
public key for macOS Remote Login on only that mini. Also add it to
`~/.orbstack/ssh/authorized_keys` on that mini and restart OrbStack as its SSH
documentation requires. Never copy the work private key to the personal mini or
vice versa.

OrbStack's generated private client key belongs to the mini. The Air should use
its own key whose public half is authorized by both SSH layers.

## Air OpenSSH configuration

Copy and edit relevant stanzas from `config/ssh/air.conf.example`. Replace the
macOS and Linux usernames. The explicit OrbStack user has the form:

```text
LINUX_USER@work-dev
```

as the `User` value for the `work-dev` host. `HostKeyAlias` prevents the work
and personal localhost endpoints from colliding in `known_hosts`.

Validate before configuring editors:

```bash
ssh -G work-dev | rg 'hostname|user|port|proxyjump|hostkeyalias'
ssh work-dev
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

The tmux server survives Air sleep, Wi-Fi changes and SSH disconnects. Reattach
with the same command. It does not survive destruction of the Ubuntu machine;
important work must be committed and pushed.
