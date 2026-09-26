# Optional Docker API access

Work or personal applications such as Testcontainers and Aspire can opt into an
SSH-forwarded OrbStack Docker API. Both profiles default to disabled. Database
administration still uses `db` and `mac docker`, and applications connect to
PostgreSQL with ordinary database credentials; neither needs this tunnel.

## Opt in

On the matching mini, enable its [Mac-Bootstrap flag](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/orbstack-docker-api.md#opt-in).
Inside its Ubuntu VM, using an up-to-date Dev-Machine checkout:

```bash
mkdir -p ~/.config/dev-machine
(umask 077; printf 'enabled\n' > ~/.config/dev-machine/docker-api-bridge)
chmod 600 ~/.config/dev-machine/docker-api-bridge
cd ~/code/dev-machine
orb/docker-api.sh
```

The guest flag is local data, never sourced as shell code. It must be a regular,
owned mode-600 file containing exactly `enabled` or `disabled`; a missing flag
means disabled. The module also reads it during normal provisioning. The flag
persists independently of the checkout. It installs the helper and user service,
but does not generate a key or start the tunnel; continue below to commission.
For a newly created VM, opt in after creation and run this targeted module.

Existing commissioned work bridges need this flag and the host flag before
applying the new module. Existing work keys/configuration remain valid. New
personal bridges receive personal-marked keys and profile-bound configuration;
copying work state does not convert it into personal state.

The matching Mac owns the real OrbStack socket. A user systemd service forwards
it to `${XDG_RUNTIME_DIR}/orbstack-docker.sock` inside Ubuntu. The runtime
directory must be owned by the VM user with mode `0700`; the socket must have
mode `0600`. No Docker daemon is installed in Ubuntu.

## Commissioning

When opted in, bootstrap installs the helper and unit without generating keys, accepting host
keys or starting a connection. The supplied Mac host policy accepts one marked
bridge authorisation per mini. Commission the matching primary VM below; a clone
requires the explicit handover described under isolation and recovery.

1. Enable Remote Login on the matching Mac. Obtain its SSH host public key and
   compare its fingerprint through a trusted separate channel. Put the verified
   key in a local known-hosts file with an entry for the hostname used below.
   An unverified `ssh-keyscan` result is insufficient.
2. On the Mac, locate the user's absolute OrbStack socket path, normally
   `$HOME/.orbstack/run/docker.sock`. Confirm ownership and socket type using
   the [Mac-Bootstrap Docker API commissioning guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/orbstack-docker-api.md).
   `MAC_HOST` below must resolve and be reachable from inside Ubuntu. The Air's
   SSH aliases and Tailscale configuration do not configure this VM-to-host
   connection; validate it separately.
3. Inside Ubuntu, initialise using the actual hostname, Mac username, absolute
   Mac socket path and verified local known-hosts file:

   ```bash
   orbstack-docker-api init MAC_HOST MAC_USER MAC_SOCKET VERIFIED_KNOWN_HOSTS
   ```

   This creates a unique Ed25519 key in
   `~/.config/dev-machine/docker-api/`. The private key stays inside this VM.
   Initialisation refuses to overwrite existing state. Display the public key
   again with `orbstack-docker-api public-key`.
4. On the matching Mac, authorise only that public key with these restrictions:

   ```text
   restrict,port-forwarding,command="/usr/bin/false" ssh-ed25519 PUBLIC_KEY_MATERIAL orbstack-docker-api-work-mini
   ```

   For personal use the comment `orbstack-docker-api-personal-mini` and its
   independently generated key. Never copy the work key.
5. Inside Ubuntu, start and verify:

   ```bash
   orbstack-docker-api start
   orbstack-docker-api verify
   ```

`start` enables the service for subsequent user sessions. It reconnects after
SSH failures and replaces its stale socket on reconnection. Verification probes
the Docker API; a socket file alone does not count as success.

## Applications

Use a command-scoped endpoint:

```bash
orbstack-docker-api run dotnet test
orbstack-docker-api run dotnet run --project PATH_TO_APPHOST
```

The wrapper sets only `DOCKER_HOST` for the launched command. Project wrappers
must supply additional Testcontainers configuration, including the engine-host
socket mount override for cleanup containers and `docker.orb.internal` for
published ports. The VM's forwarded socket is not an engine-host bind-mount
path. Validate the project configuration against the matching OrbStack engine
and keep resource cleanup enabled. Do not export these settings globally.

## Isolation and recovery

Configuration records the VM hostname. A clone with a different hostname
refuses to connect using its source VM's credentials. Before commissioning a
clone, stop its inherited service and remove only its copied
`~/.config/dev-machine/docker-api` directory after confirming the clone's
identity. The supplied Mac host verifier accepts exactly one authorisation
with the matching `orbstack-docker-api-work-mini` or
`orbstack-docker-api-personal-mini` marker. Testing a clone with the bridge
therefore requires a deliberate handover: stop the source tunnel, revoke its
marked authorisation, initialise a new clone key and authorise that key on the
Mac. Restore the primary authorisation explicitly when returning to it; do not
add a second line with the same marker. Concurrent VM bridge authorisations
require a separate host-policy change. Never rename a clone to its source
hostname to bypass the guest check.

For key rotation, stop the service, revoke the old public key on the matching
Mac, remove the exact local commissioning directory and initialise a new pair.
Do not copy work tunnel state into a personal VM. The configuration profile and VM hostname must both match; foreign state is
reported as an error even when the new profile is opted in.

```bash
orbstack-docker-api stop
journalctl --user -u dev-machine-docker-api.service
```

Docker API access grants control of the matching engine. The dedicated SSH key
cannot run shell commands, but its forwarding permission can reach other
destinations available to the Mac account. Keep it private and revoke it when
the VM is retired.

## Disable

Inside the VM, stop the service while the helper is still installed:

```bash
orbstack-docker-api stop
```

Revoke the matching marked public key on the mini, leaving unrelated entries
alone. Then, inside Ubuntu:

```bash
printf 'disabled\n' > ~/.config/dev-machine/docker-api-bridge
chmod 600 ~/.config/dev-machine/docker-api-bridge
orb/docker-api.sh
```

Run the module from the current checkout. It stops/disables the managed service
and removes the managed helper/unit. It preserves credentials and returns an
error if `~/.config/dev-machine/docker-api` remains. After confirming the host
key authorisation was revoked, remove only that exact private directory, rerun
the module, and verify. Set the matching mini flag to disabled too. Do not just
remove a flag and assume a running tunnel has stopped. Disabled verification
rejects leftover service, helper or credential state.

## References

- [OpenSSH client configuration](https://man.openbsd.org/ssh_config)
- [OrbStack Docker networking](https://docs.orbstack.dev/docker/network)
