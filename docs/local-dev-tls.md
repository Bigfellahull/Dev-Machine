# Local development TLS

The matching Mac mini issues one reusable development certificate for each
Ubuntu profile. The VM importer installs the public CA root into Ubuntu's trust
store, places the PEM material at stable user paths and creates a
password-protected PFX for .NET. It never installs `mkcert` or receives the CA
private key.

Work and personal use independent issuers, leaf keys, PFX passwords and runtime
directories. A profile marker makes the importer reject a handoff from the
other profile.

## Stable VM contract

After commissioning, the files are:

```text
~/.config/local-dev-tls/
├── root-ca.pem          # public, mode 0644
├── localhost.pem        # public leaf certificate, mode 0644
├── localhost-key.pem    # leaf private key, mode 0600
├── localhost.pfx        # leaf certificate and key, mode 0600
├── localhost.pfx-password # random secret, mode 0600
└── profile              # work or personal, mode 0644
```

The leaf covers exactly `localhost`, `127.0.0.1`, `::1`, `dev.localhost` and
`*.dev.localhost`. The importer rejects symlinks, unexpected handoff entries,
extra PEM blocks, private keys in public files, unsafe ownership or modes, an
incorrect profile, incorrect CA or server-certificate roles, a mismatched key,
a broken chain, missing or additional names and certificates near expiry.

Use `local-dev-tls paths` to print the stable paths. It does not print the PFX
password.

## Import

First export a handoff from the matching mini by following the
[Mac-Bootstrap TLS guide](https://github.com/Bigfellahull/Mac-Bootstrap/blob/main/docs/local-dev-tls.md).
Transfer it to an exact temporary directory inside the VM, then run:

```bash
local-dev-tls import /path/to/local-dev-tls-handoff
local-dev-tls verify
```

Import uses `sudo` only to install the public root under
`/usr/local/share/ca-certificates` and refresh Ubuntu's system CA bundle. The
leaf key and PFX stay owned by the VM user. Replacing different installed
material requires typing the current profile; unattended commissioning may use
`--yes` only after independently verifying the source and target profiles.
Replacement keeps exact backups of the previous user runtime and system root
until both locations and system trust have passed verification. A failure rolls
both locations back together.

Remove the exact temporary handoff from the host and VM after verification. Do
not copy `~/.config/local-dev-tls` between machines and never transfer the
mini's `rootCA-key.pem`.

## Project wrappers

Projects should read these files through their normal development wrapper and
scope variables only to the launched process. Do not export TLS paths or the
PFX password globally, and do not add any of these files to a repository.

### Caddy

Set a command-scoped directory:

```bash
LOCAL_DEV_TLS_DIR="$HOME/.config/local-dev-tls" caddy run
```

Then reference it in the Caddyfile:

```caddyfile
tls {$LOCAL_DEV_TLS_DIR}/localhost.pem {$LOCAL_DEV_TLS_DIR}/localhost-key.pem
```

This uses the shared leaf directly instead of allowing every Caddy data
directory to create another internal CA.

### Go

Pass the PEM paths to the process and load them with
`tls.LoadX509KeyPair`:

```bash
LOCAL_DEV_TLS_CERT="$HOME/.config/local-dev-tls/localhost.pem" \
LOCAL_DEV_TLS_KEY="$HOME/.config/local-dev-tls/localhost-key.pem" \
go run ./cmd/server
```

### .NET and Aspire

Kestrel can consume the generated PFX through command-scoped configuration:

```bash
tls_dir="$HOME/.config/local-dev-tls"
ASPNETCORE_Kestrel__Certificates__Default__Path="$tls_dir/localhost.pfx" \
ASPNETCORE_Kestrel__Certificates__Default__Password="$(<"$tls_dir/localhost.pfx-password")" \
dotnet run
```

An Aspire project wrapper can scope the same two variables to `dotnet run` for
the AppHost. The password remains runtime state and must not be copied into
`launchSettings.json`, appsettings or source control.

### Next.js

Next.js accepts the shared PEM files through its development HTTPS options:

```bash
tls_dir="$HOME/.config/local-dev-tls"
NODE_EXTRA_CA_CERTS="$tls_dir/root-ca.pem" \
npx next dev \
  --experimental-https \
  --experimental-https-key "$tls_dir/localhost-key.pem" \
  --experimental-https-cert "$tls_dir/localhost.pem" \
  --experimental-https-ca "$tls_dir/root-ca.pem" \
  --hostname 127.0.0.1
```

`NODE_EXTRA_CA_CERTS` also lets Node trust local services signed by the shared
CA. Keep it command-scoped. Browser trust comes from the public root installed
on the browser machine, not from this Node setting.

Binding to `127.0.0.1` avoids requiring Ubuntu to resolve a custom
`.localhost` name just to start the server. Use the browser forwarding steps
below when accessing it from the Air.

Next.js labels these HTTPS flags experimental, so project wrappers should be
tested when upgrading Next.js.

## Browsing from the Air

The certificate's `.localhost` names refer to loopback; they do not route the
Air to a VM. Once the [SSH alias](remote-access.md) is commissioned, forward the
project's HTTPS port from the Air. For a service listening on the VM's IPv4
loopback port 3000:

```bash
ssh -N -o ExitOnForwardFailure=yes -L 127.0.0.1:3000:127.0.0.1:3000 work-dev
```

Keep that SSH session open and browse to `https://localhost:3000` on the Air.
Use `personal-dev` for personal, and adjust the port and forwarding destination
to match the server's listener. The Air must trust the matching public root.
For name-based virtual hosts, use the project's covered `.localhost` name and
check that it resolves to the address used by the local forward.

## Containers and OrbStack

The Docker engine runs on macOS, so a bind mount using an Ubuntu VM path does
not refer to the same filesystem on the engine host. A project terminating TLS
inside a container must copy only the needed leaf material into a
profile-scoped host directory or Docker volume and validate the resulting file
permissions. Never copy the CA private key into a VM, container or volume.

## Renewal

The Mac mini renews the leaf and exports a fresh handoff. Reimport it with the
same command; replacement requires confirmation and preserves the existing PFX
password when that password file remains safe. Revalidate every representative
server after renewal. CA rotation is a separate commissioning event because
Ubuntu and every browser client must trust the new public root.

## References

- [Caddy `tls` directive](https://caddyserver.com/docs/caddyfile/directives/tls)
- [Kestrel endpoint certificate configuration](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/servers/kestrel)
- [Next.js CLI](https://nextjs.org/docs/app/api-reference/cli/next)
