# DockEasy System Database Restore

Use this when moving DockEasy to a new server or recovering from a server failure.

System database backups contain DockEasy metadata: users, projects, apps, domains, encrypted environment variables, tokens, settings, and backup records. They do not contain deployed app volume data and they do not contain `/etc/dockeasy/.env`.

## Critical Secret Requirement

Before restoring, copy the old server's `/etc/dockeasy/.env` to the target server.

The database backup does not include `JWT_SECRET`. DockEasy uses that secret to decrypt stored environment variables and tokens. If the target server has a different `JWT_SECRET`, the database can be restored but encrypted values cannot be recovered.

## Restore Steps

1. Install DockEasy on the target server.

2. Replace `/etc/dockeasy/.env` on the target server with the preserved file from the old server, or at minimum restore the original `JWT_SECRET` and matching database settings.

3. Copy the `.dump` file to the target server.

   ```bash
   scp dockeasy-db-2026-08-13T10-22-01.dump root@your-server:/root/
   ```

4. Run restore from the server.

   ```bash
   bash install.sh restore --restore-file=/root/dockeasy-db-2026-08-13T10-22-01.dump
   ```

   To skip the confirmation prompt:

   ```bash
   bash install.sh restore --restore-file=/root/dockeasy-db-2026-08-13T10-22-01.dump --yes
   ```

5. Sign in again after the containers restart.

The restore command automatically creates a safety dump of the current database at `/dockeasy/backups/system/pre-restore-<timestamp>.dump` before overwriting it.

## What Restore Does Not Do

- No UI restore exists by design.
- No S3 restore exists by design.
- App volume backups are separate and must be restored from the app backup tools.
- `/etc/dockeasy/.env` is never backed up automatically; keep your own secure copy.
