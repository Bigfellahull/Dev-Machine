# Recovery and rebuilds

Run lifecycle and import/export commands on the matching Mac mini from this
repository's root directory. Run project commands inside Ubuntu.

## Lost experiment machine

Recreate an experiment from its matching primary:

```bash
bin/dev clone work experiment-name
```

Use `personal` for a personal experiment. No experiment backup is expected;
push valuable source changes or move required data to its authoritative store
before deleting the machine.

A clone copies private VM state as well as tools and source. It is not a fresh
identity or a way to transfer a work setup to personal. A work clone with a
changed hostname must [commission a new Docker API key](docker-api.md#isolation-and-recovery).
Use a distinct database project name and published ports when the experiment
needs independent data: [database scopes](docker.md#isolation-model) do not
include the VM name.

## Lost primary Ubuntu machine

OrbStack Docker state is separate from the VM. If only the VM was lost, its
macOS Docker volumes can still be present. Create the missing machine:

```bash
bin/dev create work
```

Use `personal` on the personal mini. `create` refuses an existing target; inspect
`bin/dev list` before choosing a destructive rebuild instead.

Complete the [README post-provision checklist](../README.md#2-open-the-vm-and-check-provisioning):
restore private Git identity, reauthenticate, import a fresh matching TLS
handoff, restore private database configuration, and clone projects into
`~/code`. On work, revoke the lost VM's Docker API key on the Mac and commission
a new unique key. Restore project-specific configuration and validate builds,
tests, database connections and HTTPS before relying on the replacement.

When reusing existing database volumes, restore their matching credentials;
changing a password in `db.env` is not a database password rotation. Follow the
project's database procedure if the credentials are lost.

## Database volume loss

Inside the relevant project directory, recreate the container with
`db start ENGINE`, supplying the correct `--project` and `--env-file` when
needed. Restore its explicit backup using that database's tooling. Backup
retention and restore commands belong with the project because names, roles,
extensions and recovery requirements differ.

An OrbStack volume is working state, never the sole copy of important data.
VM exports do not include macOS Docker volumes.

## Mac replacement

1. Apply the matching mini profile through [Mac-Bootstrap](https://github.com/Bigfellahull/Mac-Bootstrap), including OrbStack, Tailscale and Remote Login.
2. Transfer or clone this repository as the host-side checkout and restore the matching ignored host configuration.
3. Follow the [README setup walkthrough](../README.md#start-here) to create and commission the VM. Keep work and personal credentials separate.
4. Re-establish Air access through Mac-Bootstrap and verify the replacement's SSH host fingerprints.
5. Re-establish the local TLS issuer and browser trust using the [TLS guide](local-dev-tls.md). A new CA requires explicit trust updates on every client.
6. Restore required project database backups; the old Mac's Docker volumes are not part of the new VM.
7. Validate external storage paths and, on work, Parallels independently.

## Importing a convenience export

Use an export when preserving its VM state is the intended recovery path:

```bash
scripts/restore/import-machine.sh work /Volumes/DevArchive/orbstack/machine-exports/work-dev-TIMESTAMP.tar.zst
```

The archive's `.manifest` must remain beside it with the original filename.
Imports reject missing metadata or mismatches in the selected profile, machine,
distribution, architecture or archive digest. This is a consistency check, not
a signature: both files must come from a trusted source. Legacy archives
without manifests need a separately reviewed recovery procedure.

The exact primary target must not already exist. Import restores the archive;
it does not run bootstrap, refresh packages or complete commissioning. Start
the imported VM, update it through `bin/dev provision PROFILE`, update its
Ubuntu checkout to the matching revision, and run verification inside Ubuntu.
Check restored logins, certificates and the work tunnel against the current
host. Replace stale or revoked credentials through the relevant setup guide.

Archives contain private keys and credentials. Keep them confined to their
matching profile and remember that database volumes require separate recovery.
