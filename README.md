# OpenCode Auth Migrate

Export and import OpenCode auth/provider/plugin state between machines with encrypted transfer and source-first plugin reinstall.

## What It Does

- Exports OpenCode config/auth/plugin-state data into a bundle.
- Captures plugin sources from their original references (npm/git specs and local plugin source snapshots).
- Encrypts the bundle with OpenSSL passphrase protection.
- Imports into another machine with source-first plugin restore.
- Offers fallback to full snapshot restore if source-first bootstrap fails.
- Runs one provider smoke test per provider using:
  - `Reply with exactly: PROVIDER_OK`

## Files

- `export-opencode-auth-bundle.sh`
- `import-opencode-auth-bundle.sh`
- `templates/verification-report.schema.json`

## Prerequisites

- `bash`
- `python3`
- `tar`
- `openssl`
- `opencode`

## Quick Start

1) On the source machine:

```bash
cd ~/opencode-auth-migrate
./export-opencode-auth-bundle.sh
```

2) Transfer the generated bundle from `~/opencode-auth-migrate/dist/` to the destination machine.

3) On the destination machine:

```bash
cd ~/opencode-auth-migrate
./import-opencode-auth-bundle.sh --bundle ./dist/<bundle-name>.tar.gz.enc
```

## Important Behavior

- No OpenCode version gate is enforced.
- Source-first plugin reinstall is attempted by rebuilding plugin entries from the exported manifest.
- If source-first bootstrap fails, the importer can apply fallback full snapshot restore.
- Full bundle snapshots are copied to `./imported-snapshots/` for troubleshooting.

## Options

### Export

```bash
./export-opencode-auth-bundle.sh --help
```

- `--dry-run`: detect sources/providers without creating a bundle.
- `--no-encrypt`: output plain `.tar.gz` (testing only).
- `--output <path>`: write bundle to a custom path.
- `--self-check`: dependency check.

### Import

```bash
./import-opencode-auth-bundle.sh --help
```

- `--fallback ask|always|never`: behavior if source-first bootstrap fails.
- `--dry-run`: validate and print intended actions only.
- `--self-check`: dependency check.

## Reports and Logs

- Verification reports: `./reports/import-<timestamp>/verification-report.json`
- Provider logs: `./reports/import-<timestamp>/provider-*.log`
- Bootstrap log: `./reports/import-<timestamp>/bootstrap.log`
- Automatic backups before import: `./backups/import-<timestamp>/`

## Security Notes

- Bundle encryption uses `openssl enc -aes-256-cbc -pbkdf2 -iter 200000`.
- Treat both bundle file and passphrase as sensitive.
- Remove temporary bundles when migration is complete.
