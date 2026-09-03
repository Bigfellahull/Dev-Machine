# Storage strategy

## Internal SSD: hot state

Keep OrbStack's normal data directory on the internal SSD:

- the primary Ubuntu machine and its `~/code` repositories;
- SDKs, package caches, build output and AI tools;
- Docker images and build cache;
- active project database volumes.

Do not relocate all OrbStack state merely because an external drive exists.

## External SSD: cold and recoverable state

Use a predictable work-mini volume name, defaulting to `DevArchive`, with this
starting layout:

```text
DevArchive/
  databases/
    mssql/backups/
    mssql/datasets/
    postgres/dumps/
    postgres/datasets/
  orbstack/
    machine-exports/
    volume-exports/
  parallels/backups/
  scratch/
```

Override the name only in ignored `config/local/host.env`:

```bash
DEV_EXTERNAL_VOLUME=DevArchive
```

`scripts/backup/require-external.sh` requires a mounted disk that macOS reports
as external. It rejects path separators and fails if that volume is missing,
never falling back to internal storage. The Ubuntu machine remains usable when
the drive is disconnected; only backup/dataset operations fail.

## Large databases

Keep large backups or source datasets externally, then restore into a native
OrbStack Docker volume for active work. This preserves internal latency and
makes the external asset portable.

When an internal restore is impractical, test an external bind-backed volume
with a representative workload. Record latency, throughput, fsync-heavy behavior
and failure behavior on disconnect. Do not make an external-backed active volume
the default based only on sequential benchmark speed.

## Exports

On the work mini:

```bash
scripts/backup/export-machine.sh work
```

The script writes a timestamped export and matching `.manifest` under the
required external volume. The manifest binds the archive digest, source profile,
machine, distribution and architecture. Imports reject missing, modified,
renamed or cross-profile artifacts. Exports are convenience artifacts, not a
replacement for remote Git repositories or explicit database backups.
