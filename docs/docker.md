# OrbStack Docker and databases

## Execution boundary

Applications run as ordinary Ubuntu processes. Infrastructure runs in
OrbStack's native Docker engine on macOS:

```text
dotnet/go/node/python process in Ubuntu
        |
        | database protocol to docker.orb.internal:PORT
        v
OrbStack Docker published port
        |
        v
profile-enabled, project-specific database container and volume
```

Docker administration from Ubuntu is a different path:

```text
db -> mac docker compose -> macOS Docker CLI -> OrbStack Docker engine
```

There is no nested daemon and no invented socket. `bootstrap/docker-bridge.sh`
uses OrbStack's supported `mac link docker` only when a Linux `docker` command is
absent. The `db` helper remains explicit and calls `mac docker` itself.

## First use

Inside Ubuntu, create a private credentials file:

```bash
mkdir -p ~/.config/dev-machine
cp ~/code/dev-machine/docker/db.env.example ~/.config/dev-machine/db.env
chmod 600 ~/.config/dev-machine/db.env
```

Replace every placeholder. The file is ignored and must never be committed.
The personal profile enables PostgreSQL only, so its SQL Server and Redis
placeholder values are unused. The work profile enables all three engines.
For multiple concurrently running projects, use separate files with unique
published ports:

```bash
db start postgres --project project-a --env-file ~/.config/dev-machine/project-a-db.env
db start postgres --project project-b --env-file ~/.config/dev-machine/project-b-db.env
```

Ports bind to macOS loopback rather than all LAN interfaces. Ubuntu reaches them
through `docker.orb.internal`.

## Isolation model

`db start postgres` derives the project from the current Git root. It creates a
Compose project named `PROJECT-postgres`; the other engines use analogous names.
Each engine therefore has its own container and named data volume. Image layers
and build cache remain shared in OrbStack.

`db --help` lists the engines installed for the current machine. Personal
machines expose only PostgreSQL. Work machines additionally expose SQL Server
and Redis, and `db status` checks only the enabled set. Reprovisioning removes
stale managed Compose definitions when a profile does not enable them; it never
removes the corresponding macOS Docker volumes.

`db reset ENGINE` runs `compose down --volumes` only for the exact
`PROJECT-ENGINE` scope and requires confirmation. It does not remove shared
images or another project's data.

Useful commands:

```bash
db status
db logs postgres
db stop postgres
db restart postgres
db pull postgres
db connection postgres
```

## Image policy

PostgreSQL and Redis use explicit patch tags in `docker/images.env`. SQL Server
uses the SQL Server 2025 servicing tag. Pulling a new image is deliberate; data
remains in named volumes. Record image digests during commissioning when an
exact recovery record is required.

## SQL Server on Apple Silicon

This is the important exception. Microsoft publishes SQL Server Linux
containers only for Intel/AMD x86-64 and states that Rosetta, QEMU and similar
translation environments are untested and unsupported. The Compose definition
therefore declares `platform: linux/amd64` and `db start mssql` prints a warning.

It is suitable only as a development experiment after commissioning verifies
correctness and performance. It is not a supported production topology. If it
is inadequate, the supported alternatives are an external x86-64 SQL Server or
a managed service; this repository must not couple the independent Parallels VM
into OrbStack provisioning.

Microsoft documents this limitation in its
[SQL Server Linux platform guidance](https://learn.microsoft.com/sql/linux/install-upgrade/setup?view=sql-server-ver17).

## Host Compose verification

A clean OrbStack install includes Compose. Verify on each mini:

```bash
docker context show
docker compose version
```

If the command is absent, inspect Docker CLI plugin paths before changing
anything. A broken `/usr/local/lib/docker/cli-plugins` link may point to an
absent Docker Desktop bundle. Do not install Docker Desktop to repair the link;
use OrbStack's installation and diagnostics instead.
