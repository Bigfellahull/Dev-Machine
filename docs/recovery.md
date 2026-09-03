# Recovery and rebuilds

## Lost experiment machine

Experiments are disposable. Recreate from the primary machine:

```bash
bin/dev clone work experiment-name
```

No backup is expected. Anything valuable must be committed or moved to an
authoritative store before deletion.

## Lost primary Ubuntu machine

OrbStack Docker state is separate and should remain intact:

```bash
bin/dev create work
```

Then authenticate GitHub and AI providers, restore private Git identity, clone
repositories into `~/code`, and run `bootstrap/verify.sh`. Test representative
.NET and Go builds. Do not restore a machine export by default when a clean
rebuild is the acceptance goal.

## Database volume loss

Recreate the project container with `db start ENGINE`, then restore the explicit
project backup using that database's standard tooling. Database-specific backup
retention and restore commands belong with the project because names, roles,
extensions and recovery requirements differ.

An OrbStack volume is working state, never the sole copy of important data.

## Mac replacement

1. Install macOS updates, OrbStack and Tailscale; enable Remote Login.
2. Transfer or clone this repository as the host-side bootstrap checkout.
3. Restore only ignored host configuration, never bulk-copy credentials between
   work and personal.
4. Run `bin/dev create PROFILE`.
5. Re-establish the Air's SSH authorization and test the jump alias.
6. Reauthenticate inside Ubuntu and clone project repositories.
7. Restore only database state that is actually required.
8. Validate external storage paths and, on work, Parallels independently.

## Importing a convenience export

Only when a clean rebuild is not the desired recovery path:

```bash
scripts/restore/import-machine.sh work /Volumes/DevArchive/orbstack/machine-exports/work-dev-TIMESTAMP.tar.zst
```

The archive's `.manifest` must remain beside it with the original filename.
Imports fail closed when provenance is missing or does not match the selected
profile, machine, distribution, architecture or archive digest; legacy exports
without a manifest must be replaced by a verified export or recovered manually.
The exact primary target must not already exist. After import, rerun verification
and update provisioning normally; an export may contain stale packages or state.
