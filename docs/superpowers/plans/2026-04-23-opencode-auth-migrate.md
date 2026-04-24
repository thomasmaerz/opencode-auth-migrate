# OpenCode Auth Migrate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build export/import scripts that migrate OpenCode provider credentials and community auth plugin state to another machine, reinstall plugins from original sources first, and run one-provider smoke tests.

**Architecture:** Use two POSIX shell scripts. The export script snapshots relevant OpenCode config/auth/plugin-state areas plus local plugin source trees and emits a manifest, then encrypts the bundle. The import script decrypts, backs up destination state, restores auth/plugin-state, reconstructs plugin sources, applies source-first plugin config, attempts bootstrap, and optionally falls back to full snapshot restore if source-first bootstrap fails.

**Tech Stack:** Bash, Python 3 (JSON transforms), tar, openssl, sha256sum/shasum, OpenCode CLI.

---

### Task 1: Scaffold Project Files

**Files:**
- Create: `opencode-auth-migrate/export-opencode-auth-bundle.sh`
- Create: `opencode-auth-migrate/import-opencode-auth-bundle.sh`
- Create: `opencode-auth-migrate/README.md`
- Create: `opencode-auth-migrate/templates/verification-report.schema.json`

- [ ] **Step 1: Create executable script skeletons**

```bash
#!/usr/bin/env bash
set -euo pipefail

main() {
  echo "not implemented"
}

main "$@"
```

- [ ] **Step 2: Set executable bits**

Run: `chmod +x ~/opencode-auth-migrate/export-opencode-auth-bundle.sh ~/opencode-auth-migrate/import-opencode-auth-bundle.sh`
Expected: no output, exit 0

- [ ] **Step 3: Commit scaffold**

```bash
git add ~/opencode-auth-migrate
git commit -m "chore: scaffold opencode auth migration scripts"
```

### Task 2: Implement Export Bundle Builder

**Files:**
- Modify: `opencode-auth-migrate/export-opencode-auth-bundle.sh`
- Test: `opencode-auth-migrate/export-opencode-auth-bundle.sh` (self-check mode)

- [ ] **Step 1: Add a failing self-check mode contract**

```bash
if [[ "${1:-}" == "--self-check" ]]; then
  echo "SELF_CHECK_NOT_IMPLEMENTED"
  exit 1
fi
```

- [ ] **Step 2: Run self-check and verify failure**

Run: `~/opencode-auth-migrate/export-opencode-auth-bundle.sh --self-check`
Expected: exits non-zero with `SELF_CHECK_NOT_IMPLEMENTED`

- [ ] **Step 3: Implement export logic with manifest + encryption**

```bash
if [[ "${1:-}" == "--self-check" ]]; then
  command -v python3 >/dev/null
  command -v openssl >/dev/null
  echo "SELF_CHECK_OK"
  exit 0
fi

# 1) detect source dirs and files
# 2) collect plugin list from ~/.config/opencode/opencode.json and config.json
# 3) classify plugin entries into npm/git/local
# 4) copy local plugin trees into bundle/plugins/local/<token>
# 5) copy auth + plugin account stores + config snapshots
# 6) write manifest.json + checksums
# 7) tar bundle and encrypt with openssl pbkdf2
```

- [ ] **Step 4: Run self-check and verify pass**

Run: `~/opencode-auth-migrate/export-opencode-auth-bundle.sh --self-check`
Expected: `SELF_CHECK_OK`

- [ ] **Step 5: Commit export script**

```bash
git add ~/opencode-auth-migrate/export-opencode-auth-bundle.sh
git commit -m "feat: add encrypted export bundle builder"
```

### Task 3: Implement Importer with Source-First Reinstall and Fallback

**Files:**
- Modify: `opencode-auth-migrate/import-opencode-auth-bundle.sh`
- Test: `opencode-auth-migrate/import-opencode-auth-bundle.sh` (self-check mode)

- [ ] **Step 1: Add a failing self-check mode contract**

```bash
if [[ "${1:-}" == "--self-check" ]]; then
  echo "SELF_CHECK_NOT_IMPLEMENTED"
  exit 1
fi
```

- [ ] **Step 2: Run self-check and verify failure**

Run: `~/opencode-auth-migrate/import-opencode-auth-bundle.sh --self-check`
Expected: exits non-zero with `SELF_CHECK_NOT_IMPLEMENTED`

- [ ] **Step 3: Implement source-first import flow**

```bash
if [[ "${1:-}" == "--self-check" ]]; then
  command -v python3 >/dev/null
  command -v tar >/dev/null
  echo "SELF_CHECK_OK"
  exit 0
fi

# 1) parse --bundle
# 2) decrypt and extract
# 3) validate manifest + checksums
# 4) create timestamped backups of destination files/dirs
# 5) restore auth + plugin account stores
# 6) copy exported local plugin sources to ~/.config/opencode/plugins-migrated
# 7) rewrite target plugin array from manifest source specs
# 8) run OpenCode bootstrap command
# 9) if bootstrap fails, prompt for fallback snapshot restore
```

- [ ] **Step 4: Implement provider smoke tests and report generation**

```bash
# For each provider in auth/config:
# - choose model from config provider.<id>.models first key, else opencode models <provider>
# - run opencode run -m provider/model "Reply with exactly: PROVIDER_OK"
# - record pass/fail/skip in verification-report.json
```

- [ ] **Step 5: Run self-check and verify pass**

Run: `~/opencode-auth-migrate/import-opencode-auth-bundle.sh --self-check`
Expected: `SELF_CHECK_OK`

- [ ] **Step 6: Commit import script**

```bash
git add ~/opencode-auth-migrate/import-opencode-auth-bundle.sh
git commit -m "feat: add source-first import with fallback restore"
```

### Task 4: Add Operator Documentation and Report Schema

**Files:**
- Modify: `opencode-auth-migrate/README.md`
- Modify: `opencode-auth-migrate/templates/verification-report.schema.json`

- [ ] **Step 1: Write operator README with explicit workflow**

```markdown
# OpenCode Auth Migrate

1. Run export on source machine
2. Transfer encrypted bundle
3. Run import on destination machine
4. Review verification report

Includes source-first plugin reinstall and optional fallback snapshot restore.
```

- [ ] **Step 2: Add JSON schema for verification report**

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "required": ["created_at", "results"],
  "properties": {
    "created_at": { "type": "string" },
    "results": {
      "type": "array",
      "items": {
        "type": "object",
        "required": ["provider", "status"],
        "properties": {
          "provider": { "type": "string" },
          "status": { "enum": ["pass", "fail", "skip"] }
        }
      }
    }
  }
}
```

- [ ] **Step 3: Commit docs and schema**

```bash
git add ~/opencode-auth-migrate/README.md ~/opencode-auth-migrate/templates/verification-report.schema.json
git commit -m "docs: add migration runbook and verification schema"
```

### Task 5: Verification

**Files:**
- Test: `opencode-auth-migrate/export-opencode-auth-bundle.sh`
- Test: `opencode-auth-migrate/import-opencode-auth-bundle.sh`

- [ ] **Step 1: Run shell syntax checks**

Run: `bash -n ~/opencode-auth-migrate/export-opencode-auth-bundle.sh ~/opencode-auth-migrate/import-opencode-auth-bundle.sh`
Expected: no output, exit 0

- [ ] **Step 2: Run script self-checks**

Run: `~/opencode-auth-migrate/export-opencode-auth-bundle.sh --self-check && ~/opencode-auth-migrate/import-opencode-auth-bundle.sh --self-check`
Expected: both print `SELF_CHECK_OK`

- [ ] **Step 3: Run an export dry run**

Run: `~/opencode-auth-migrate/export-opencode-auth-bundle.sh --dry-run`
Expected: prints resolved paths, detected providers/plugins, and exits 0 without writing bundle

- [ ] **Step 4: Commit final verification changes**

```bash
git add ~/opencode-auth-migrate
git commit -m "test: verify migration scripts with self-check and dry-run"
```
