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

## Choose Your Workflow

This project provides three migration paths:

### Path 1: Deterministic Script Mode (Recommended for reproducibility)

Use the shell scripts directly for fully automated, reproducible migrations.

Best fit: perfect for moving between the same OpenCode version when plugins are already up to date.

| Feature | Value |
|---------|-------|
| Determinism | High |
| Web dependency | None |
| Plugin update behavior | Uses exported sources |
| User prompts | None |

Quick start:
```bash
./export-opencode-auth-bundle.sh
./import-opencode-auth-bundle.sh --bundle ./dist/<bundle>.tar.gz.enc
```

Files: `export-opencode-auth-bundle.sh`, `import-opencode-auth-bundle.sh`

### Path 2: Agentic Prompt-Only Mode

Give the playbook prompts to an AI agent for ecosystem-aware decisions.

Best fit: recommended when migrating between different OpenCode versions.

| Feature | Value |
|---------|-------|
| Determinism | Medium |
| Web dependency | Reads ecosystem page |
| Plugin update behavior | Checks ecosystem first, falls back |
| User prompts | On fallback decisions |

Quick start:
```bash
# Give the agent these prompts:
# - Paste contents of playbooks/auth-export-playbook.md
# - Paste contents of playbooks/auth-import-playbook.md
```

Files: `playbooks/auth-export-playbook.md`, `playbooks/auth-import-playbook.md`

### Path 3: Agentic Command Mode

Use OpenCode commands that execute playbooks automatically.

Best fit: recommended when migrating between different OpenCode versions.

| Feature | Value |
|---------|-------|
| Determinism | Medium |
| Web dependency | Reads ecosystem page |
| Plugin update behavior | Checks ecosystem first, falls back |
| User prompts | On fallback decisions |

Quick start:
```bash
opencode @.opencode/commands/auth-export-agentic.md
opencode @.opencode/commands/auth-import-agentic.md
```

Files: `.opencode/commands/auth-export-agentic.md`, `.opencode/commands/auth-import-agentic.md`

## Ecosystem-First Reinstall

For agentic paths (2 and 3), plugins are reinstalled as follows:

1. Read `https://opencode.ai/docs/ecosystem/` to discover available plugins
2. For each incoming plugin, check if ecosystem has a compatible version
3. Follow linked plugin repo README.md install instructions
4. Prefer latest stable release, fall back to default branch
5. If reinstall fails, prompt user for fallback decision

### Manual guard22 Override

The `guard22/opencode-multi-auth-codex` plugin is not consistently listed on the ecosystem page but is available at:

- Repo: https://github.com/guard22/opencode-multi-auth-codex
- Install from this repo if not found on ecosystem

## Files

- `export-opencode-auth-bundle.sh` - Export script
- `import-opencode-auth-bundle.sh` - Import script
- `catalog/stock-auth-plugins.json` - Stock (built-in) auth plugins
- `catalog/manual-ecosystem-overrides.json` - Manual ecosystem overrides
- `tools/refresh-stock-auth-plugins.py` - Optional catalog refresh tool
- `playbooks/auth-export-playbook.md` - Export playbook prompt
- `playbooks/auth-import-playbook.md` - Import playbook prompt
- `.opencode/commands/auth-export-agentic.md` - Export command
- `.opencode/commands/auth-import-agentic.md` - Import command
- `templates/agentic-import-report.schema.json` - Agentic import report schema
- `templates/verification-report.schema.json` - Verification report schema

## Prerequisites

- `bash`
- `python3`
- `tar`
- `openssl`
- `opencode`

## Quick Start (Deterministic)

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

## Non-Stock Auth Plugins

The export script detects and reports non-stock auth plugins by comparing against `catalog/stock-auth-plugins.json`:

- Stock plugins: `opencode-openai-codex-auth`, `opencode-gemini-auth`, `opencode-antigravity-auth`, `opencode-google-antigravity-auth`
- Any plugin not in stock is reported as non-stock in the export manifest

## Options

### Export

```bash
./export-opencode-auth-bundle.sh --help
```

- `--dry-run`: detect sources/providers without creating a bundle.
- `--no-encrypt`: output plain `.tar.gz` (testing only).
- `--output <path>`: write bundle to a custom path.
- `--self-check`: dependency check.
- `--refresh-stock`: refresh stock plugin catalog before classifying.
- `--stock-source local|refresh|auto`: source for stock plugins.

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
