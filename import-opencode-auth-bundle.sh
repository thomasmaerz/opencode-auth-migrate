#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR/.work"
BACKUP_DIR="$SCRIPT_DIR/backups"
IMPORTED_SNAPSHOTS_DIR="$SCRIPT_DIR/imported-snapshots"
REPORTS_DIR="$SCRIPT_DIR/reports"
TEST_PROMPT="Reply with exactly: PROVIDER_OK"

SELF_CHECK=0
DRY_RUN=0
BUNDLE_PATH=""
FALLBACK_MODE="ask" # ask|always|never

log() {
  printf '[import] %s\n' "$*"
}

warn() {
  printf '[import][warn] %s\n' "$*" >&2
}

die() {
  printf '[import][error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: import-opencode-auth-bundle.sh --bundle <path> [options]

Options:
  --bundle <path>      Path to encrypted bundle (.tar.gz.enc) or plain bundle (.tar.gz)
  --fallback <mode>    Fallback behavior when source-first bootstrap fails: ask|always|never
  --dry-run            Validate and print planned actions only
  --self-check         Validate runtime dependencies only
  -h, --help           Show this help

Behavior:
  1) Decrypt/extract bundle
  2) Backup destination state
  3) Restore auth/plugin state
  4) Reinstall plugins from manifest sources (source-first)
  5) Offer fallback full snapshot restore if source-first bootstrap fails
  6) Run one provider smoke test per provider
EOF
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --bundle)
        [[ $# -ge 2 ]] || die "--bundle requires a value"
        BUNDLE_PATH="$2"
        shift 2
        ;;
      --fallback)
        [[ $# -ge 2 ]] || die "--fallback requires a value"
        FALLBACK_MODE="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --self-check)
        SELF_CHECK=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done

  if [[ "$SELF_CHECK" -eq 0 && -z "$BUNDLE_PATH" ]]; then
    die "--bundle is required"
  fi

  case "$FALLBACK_MODE" in
    ask|always|never) ;;
    *) die "--fallback must be one of: ask, always, never" ;;
  esac
}

run_self_check() {
  require_cmd python3
  require_cmd tar
  require_cmd openssl
  require_cmd opencode
  echo "SELF_CHECK_OK"
}

decrypt_if_needed() {
  local source_bundle="$1"
  local out_tar="$2"
  if [[ "$source_bundle" == *.enc ]]; then
    log "decrypting bundle (passphrase prompt expected)"
    openssl enc -d -aes-256-cbc -pbkdf2 -in "$source_bundle" -out "$out_tar"
  else
    cp "$source_bundle" "$out_tar"
  fi
}

locate_bundle_root() {
  local extracted_dir="$1"
  local entries=("$extracted_dir"/*)
  [[ ${#entries[@]} -eq 1 ]] || die "expected exactly one root folder in extracted bundle"
  [[ -d "${entries[0]}" ]] || die "bundle root is not a directory: ${entries[0]}"
  printf '%s\n' "${entries[0]}"
}

verify_checksums() {
  local bundle_root="$1"
  python3 - "$bundle_root" <<'PY'
import hashlib
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
checksum_file = root / "checksums" / "sha256.txt"
if not checksum_file.exists():
    print("[import][error] checksums/sha256.txt missing", file=sys.stderr)
    sys.exit(1)

def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()

failed = []
with checksum_file.open("r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        parts = line.split("  ", 1)
        if len(parts) != 2:
            failed.append(("format", line))
            continue
        expected, rel = parts
        path = root / rel
        if not path.exists():
            failed.append(("missing", rel))
            continue
        actual = digest(path)
        if actual != expected:
            failed.append(("mismatch", rel))

if failed:
    for reason, rel in failed:
        print(f"[import][error] checksum {reason}: {rel}", file=sys.stderr)
    sys.exit(1)

print("[import] checksum verification passed")
PY
}

backup_current_state() {
  local manifest_path="$1"
  local backup_root="$2"
  local dest_config_dir="$3"
  local dest_auth_file="$4"
  local dest_multi_auth_dir="$5"

  python3 - "$manifest_path" "$backup_root" "$dest_config_dir" "$dest_auth_file" "$dest_multi_auth_dir" <<'PY'
import json
import shutil
import sys
from pathlib import Path

_manifest = Path(sys.argv[1])
backup_root = Path(sys.argv[2])
dest_config_dir = Path(sys.argv[3])
dest_auth_file = Path(sys.argv[4])
dest_multi_auth_dir = Path(sys.argv[5])

backup_root.mkdir(parents=True, exist_ok=True)

def copy_dir(src: Path, dst: Path):
    if not src.exists() or not src.is_dir():
        return
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)

def copy_file(src: Path, dst: Path):
    if not src.exists() or not src.is_file():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

copy_dir(dest_config_dir, backup_root / "config" / "opencode")
copy_file(dest_auth_file, backup_root / "data" / "opencode" / "auth.json")
copy_dir(dest_multi_auth_dir, backup_root / "plugin-state" / "opencode-multi-auth")
PY
}

restore_source_first_state() {
  local bundle_root="$1"
  local imported_snapshot_root="$2"
  local dest_config_dir="$3"
  local dest_auth_file="$4"
  local dest_multi_auth_dir="$5"

  python3 - "$bundle_root" "$imported_snapshot_root" "$dest_config_dir" "$dest_auth_file" "$dest_multi_auth_dir" <<'PY'
import shutil
import sys
from pathlib import Path

bundle_root = Path(sys.argv[1])
imported_snapshot_root = Path(sys.argv[2])
dest_config_dir = Path(sys.argv[3])
dest_auth_file = Path(sys.argv[4])
dest_multi_auth_dir = Path(sys.argv[5])

snapshots = bundle_root / "snapshots"

def copy_dir(src: Path, dst: Path):
    if not src.exists() or not src.is_dir():
        return False
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)
    return True

def copy_file(src: Path, dst: Path):
    if not src.exists() or not src.is_file():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return True

imported_snapshot_root.mkdir(parents=True, exist_ok=True)
copy_dir(snapshots, imported_snapshot_root / "snapshots")

copy_file(snapshots / "data" / "opencode" / "auth.json", dest_auth_file)
copy_dir(snapshots / "plugin-state" / "opencode-multi-auth", dest_multi_auth_dir)

source_config_dir = snapshots / "config" / "opencode"
if source_config_dir.exists() and source_config_dir.is_dir():
    dest_config_dir.mkdir(parents=True, exist_ok=True)
    for file_path in source_config_dir.iterdir():
        if not file_path.is_file():
            continue
        name = file_path.name
        if name in {"opencode.json", "config.json"}:
            continue
        if name.endswith("-accounts.json") or name in {"antigravity.json", "puter.json"}:
            shutil.copy2(file_path, dest_config_dir / name)
PY
}

apply_plugin_sources_and_config() {
  local bundle_root="$1"
  local dest_config_dir="$2"
  local runtime_json="$3"

  python3 - "$bundle_root" "$dest_config_dir" "$runtime_json" <<'PY'
import json
import shutil
import sys
from pathlib import Path

bundle_root = Path(sys.argv[1])
dest_config_dir = Path(sys.argv[2])
runtime_json = Path(sys.argv[3])

manifest_path = bundle_root / "manifest.json"
with manifest_path.open("r", encoding="utf-8") as f:
    manifest = json.load(f)

plugins = manifest.get("plugins", [])
local_sources_root = bundle_root / "plugin-sources" / "local"
dest_local_root = dest_config_dir / "plugins-migrated"
dest_local_root.mkdir(parents=True, exist_ok=True)

opencode_json_path = dest_config_dir / "opencode.json"
existing_plugins = []
if opencode_json_path.exists():
    try:
        with opencode_json_path.open("r", encoding="utf-8") as f:
            existing = json.load(f)
        if isinstance(existing, dict) and isinstance(existing.get("plugin"), list):
            existing_plugins = [str(p) for p in existing["plugin"] if isinstance(p, str)]
    except Exception:
        pass

def normalize_plugin(entry: str) -> str:
    normalized = entry.strip()
    normalized = normalized.rstrip("/")
    for suffix in ["@latest", "@main", "@master"]:
        if normalized.endswith(suffix):
            normalized = normalized[: -len(suffix)]
    return normalized

def plugin_matches(existing: str, incoming: str) -> bool:
    existing_norm = normalize_plugin(existing)
    incoming_norm = normalize_plugin(incoming)
    if existing_norm == incoming_norm:
        return True
    if existing_norm.endswith(incoming_norm) or incoming_norm.endswith(existing_norm):
        return True
    return False

resolved_plugin_entries = []
plugin_results = []

for plugin in plugins:
    kind = plugin.get("kind")
    source_spec = plugin.get("source_spec")
    action = "installed"
    matched_existing = None
    
    for existing in existing_plugins:
        if plugin_matches(existing, source_spec):
            matched_existing = existing
            action = "skipped_already_present"
            break
    
    if kind == "local":
        token = plugin.get("token")
        src = local_sources_root / str(token)
        dst = dest_local_root / str(token)
        copied = False
        if action == "installed" and src.exists():
            if dst.exists():
                shutil.rmtree(dst)
            shutil.copytree(src, dst)
            copied = True
            resolved_plugin_entries.append(str(dst))
        plugin_results.append({
            "kind": kind,
            "source_spec": source_spec,
            "token": token,
            "copied": copied,
            "action": action,
            "matched_existing": matched_existing,
            "resolved_entry": str(dst) if copied else None,
        })
    else:
        if action == "installed":
            if isinstance(source_spec, str) and source_spec:
                resolved_plugin_entries.append(source_spec)
        plugin_results.append({
            "kind": kind,
            "source_spec": source_spec,
            "copied": None,
            "action": action,
            "matched_existing": matched_existing,
            "resolved_entry": source_spec if action == "installed" else None,
        })

deduped = []
seen = set()
for entry in resolved_plugin_entries:
    if entry in seen:
        continue
    seen.add(entry)
    deduped.append(entry)

dest_config_dir.mkdir(parents=True, exist_ok=True)
data = {}
if opencode_json_path.exists():
    try:
        with opencode_json_path.open("r", encoding="utf-8") as f:
            loaded = json.load(f)
        if isinstance(loaded, dict):
            data = loaded
    except Exception:
        data = {}

if "$schema" not in data:
    data["$schema"] = "https://opencode.ai/config.json"
data["plugin"] = deduped

with opencode_json_path.open("w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)

runtime = {
    "plugin_results": plugin_results,
    "resolved_plugins": deduped,
    "opencode_json_path": str(opencode_json_path),
    "existing_plugins": existing_plugins,
    "plugin_actions": [{"plugin": r.get("source_spec"), "action": r.get("action")} for r in plugin_results],
}
with runtime_json.open("w", encoding="utf-8") as f:
    json.dump(runtime, f, indent=2)
PY
}

restore_full_snapshot() {
  local bundle_root="$1"
  local dest_config_dir="$2"
  local dest_auth_file="$3"
  local dest_multi_auth_dir="$4"

  python3 - "$bundle_root" "$dest_config_dir" "$dest_auth_file" "$dest_multi_auth_dir" <<'PY'
import shutil
import sys
from pathlib import Path

bundle_root = Path(sys.argv[1])
dest_config_dir = Path(sys.argv[2])
dest_auth_file = Path(sys.argv[3])
dest_multi_auth_dir = Path(sys.argv[4])
snapshots = bundle_root / "snapshots"

def replace_dir(src: Path, dst: Path):
    if not src.exists() or not src.is_dir():
        return
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)

def replace_file(src: Path, dst: Path):
    if not src.exists() or not src.is_file():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

replace_dir(snapshots / "config" / "opencode", dest_config_dir)
replace_file(snapshots / "data" / "opencode" / "auth.json", dest_auth_file)
replace_dir(snapshots / "plugin-state" / "opencode-multi-auth", dest_multi_auth_dir)
PY
}

should_use_fallback() {
  case "$FALLBACK_MODE" in
    always)
      return 0
      ;;
    never)
      return 1
      ;;
    ask)
      printf 'Source-first bootstrap failed. Fallback to full snapshot restore? [y/N]: ' >&2
      local ans
      IFS= read -r ans || true
      case "$ans" in
        y|Y|yes|YES) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
}

bootstrap_source_first() {
  local bootstrap_log="$1"
  if opencode models >"$bootstrap_log" 2>&1; then
    return 0
  fi
  return 1
}

run_provider_verification() {
  local dest_auth_file="$1"
  local dest_config_file="$2"
  local report_json="$3"
  local report_dir="$4"
  local dry_run="$5"

  python3 - "$dest_auth_file" "$dest_config_file" "$report_json" "$report_dir" "$TEST_PROMPT" "$dry_run" <<'PY'
import datetime as dt
import json
import re
import subprocess
import sys
from pathlib import Path

auth_file = Path(sys.argv[1])
config_file = Path(sys.argv[2])
report_json = Path(sys.argv[3])
report_dir = Path(sys.argv[4])
prompt = sys.argv[5]
dry_run = sys.argv[6] == "1"

report_dir.mkdir(parents=True, exist_ok=True)

def load_json(path: Path):
    if not path.exists():
        return {}
    try:
        with path.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            return data
    except Exception:
        pass
    return {}

auth = load_json(auth_file)
cfg = load_json(config_file)
provider_cfg = cfg.get("provider", {}) if isinstance(cfg.get("provider", {}), dict) else {}

providers = []
for p in provider_cfg.keys():
    if isinstance(p, str) and p not in providers:
        providers.append(p)
for p in auth.keys():
    if isinstance(p, str) and p not in providers:
        providers.append(p)

def first_config_model(provider: str):
    item = provider_cfg.get(provider, {})
    if not isinstance(item, dict):
        return None
    models = item.get("models", {})
    if isinstance(models, dict):
        for key in models.keys():
            if isinstance(key, str) and key:
                return key
    return None

def first_cli_model(provider: str):
    try:
        proc = subprocess.run(["opencode", "models", provider], capture_output=True, text=True, timeout=30)
    except Exception:
        return None
    text = (proc.stdout or "") + "\n" + (proc.stderr or "")
    pattern = re.compile(rf"{re.escape(provider)}/[A-Za-z0-9._:/-]+")
    match = pattern.search(text)
    if match:
        return match.group(0)
    return None

results = []

for provider in providers:
    model = first_config_model(provider)
    if model is None:
        model = first_cli_model(provider)

    if model is None:
        results.append({
            "provider": provider,
            "model": None,
            "status": "skip",
            "reason": "no-model-found",
        })
        continue

    model_ref = model if model.startswith(provider + "/") else f"{provider}/{model}"
    safe_name = re.sub(r"[^A-Za-z0-9._-]+", "_", provider)
    log_file = report_dir / f"provider-{safe_name}.log"

    if dry_run:
        results.append({
            "provider": provider,
            "model": model_ref,
            "status": "skip",
            "reason": "dry-run",
            "log_file": str(log_file),
        })
        continue

    try:
        proc = subprocess.run(
            ["opencode", "run", "-m", model_ref, prompt],
            capture_output=True,
            text=True,
            timeout=300,
        )
        output = (proc.stdout or "") + "\n" + (proc.stderr or "")
        with log_file.open("w", encoding="utf-8") as f:
            f.write(output)
        ok = proc.returncode == 0 and "PROVIDER_OK" in output
        results.append({
            "provider": provider,
            "model": model_ref,
            "status": "pass" if ok else "fail",
            "exit_code": proc.returncode,
            "contains_expected_text": "PROVIDER_OK" in output,
            "log_file": str(log_file),
        })
    except subprocess.TimeoutExpired:
        with log_file.open("w", encoding="utf-8") as f:
            f.write("timeout after 300s\n")
        results.append({
            "provider": provider,
            "model": model_ref,
            "status": "fail",
            "reason": "timeout",
            "log_file": str(log_file),
        })

report = {
    "schema_version": 1,
    "created_at": dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
    "prompt": prompt,
    "results": results,
}

with report_json.open("w", encoding="utf-8") as f:
    json.dump(report, f, indent=2)
PY
}

print_report_summary() {
  local report_json="$1"
  python3 - "$report_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
with path.open("r", encoding="utf-8") as f:
    report = json.load(f)

results = report.get("results", [])
pass_count = len([r for r in results if r.get("status") == "pass"])
fail_count = len([r for r in results if r.get("status") == "fail"])
skip_count = len([r for r in results if r.get("status") == "skip"])

print(f"[import] provider verification: pass={pass_count} fail={fail_count} skip={skip_count}")
for item in results:
    provider = item.get("provider")
    status = item.get("status")
    model = item.get("model")
    reason = item.get("reason")
    if reason:
        print(f"[import] - {provider}: {status} ({reason})")
    else:
        print(f"[import] - {provider}: {status} ({model})")
PY
}

main() {
  parse_args "$@"

  if [[ "$SELF_CHECK" -eq 1 ]]; then
    run_self_check
    return 0
  fi

  require_cmd python3
  require_cmd tar
  require_cmd openssl
  require_cmd opencode

  [[ -f "$BUNDLE_PATH" ]] || die "bundle file not found: $BUNDLE_PATH"

  local timestamp
  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  mkdir -p "$WORK_DIR" "$BACKUP_DIR" "$IMPORTED_SNAPSHOTS_DIR" "$REPORTS_DIR"

  local temp_root
  temp_root="$(mktemp -d "$WORK_DIR/import.XXXXXX")"
  trap 'rm -rf '"'"'"$temp_root"'"'"'' EXIT

  local decrypted_tar="$temp_root/bundle.tar.gz"
  local extracted_dir="$temp_root/extracted"
  mkdir -p "$extracted_dir"

  decrypt_if_needed "$BUNDLE_PATH" "$decrypted_tar"
  tar -xzf "$decrypted_tar" -C "$extracted_dir"

  local bundle_root
  bundle_root="$(locate_bundle_root "$extracted_dir")"
  local manifest_path="$bundle_root/manifest.json"
  [[ -f "$manifest_path" ]] || die "manifest missing: $manifest_path"

  verify_checksums "$bundle_root"

  local dest_config_dir="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
  local dest_data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
  local dest_auth_file="$dest_data_dir/auth.json"
  local dest_multi_auth_dir="${OPENCODE_MULTI_AUTH_STORE_DIR:-$HOME/.config/opencode-multi-auth}"
  local dest_config_file="$dest_config_dir/opencode.json"

  local backup_root="$BACKUP_DIR/import-$timestamp"
  local imported_snapshot_root="$IMPORTED_SNAPSHOTS_DIR/import-$timestamp"
  local report_root="$REPORTS_DIR/import-$timestamp"
  mkdir -p "$report_root"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "dry run mode enabled"
    log "bundle: $BUNDLE_PATH"
    log "bundle root: $bundle_root"
    log "destination config dir: $dest_config_dir"
    log "destination auth file: $dest_auth_file"
    log "destination multi-auth dir: $dest_multi_auth_dir"
    log "backup root: $backup_root"
    log "imported snapshots dir: $imported_snapshot_root"
  else
    backup_current_state "$manifest_path" "$backup_root" "$dest_config_dir" "$dest_auth_file" "$dest_multi_auth_dir"
    restore_source_first_state "$bundle_root" "$imported_snapshot_root" "$dest_config_dir" "$dest_auth_file" "$dest_multi_auth_dir"
    apply_plugin_sources_and_config "$bundle_root" "$dest_config_dir" "$report_root/runtime.json"
  fi

  if [[ -f "$report_root/runtime.json" ]]; then
    python3 - "$report_root/runtime.json" <<'PY'
import json
import sys
from pathlib import Path
rt_path = Path(sys.argv[1])
with rt_path.open("r") as f:
    rt = json.load(f)
actions = rt.get("plugin_actions", [])
print("[import] plugin actions:")
for a in actions:
    src = a.get("plugin", "unknown")
    act = a.get("action", "unknown")
    matched = a.get("matched_existing")
    if matched:
        print(f"[import] - {src}: {act} (matches existing: {matched})")
    else:
        print(f"[import] - {src}: {act}")
PY
  fi

  local bootstrap_log="$report_root/bootstrap.log"
  local bootstrap_failed=0
  if [[ "$DRY_RUN" -eq 1 ]]; then
    log "skipping bootstrap in dry run"
  else
    if bootstrap_source_first "$bootstrap_log"; then
      log "source-first bootstrap succeeded"
    else
      bootstrap_failed=1
      warn "source-first bootstrap failed (see $bootstrap_log)"
      if should_use_fallback; then
        log "applying fallback full snapshot restore"
        restore_full_snapshot "$bundle_root" "$dest_config_dir" "$dest_auth_file" "$dest_multi_auth_dir"
      else
        warn "fallback not applied"
      fi
    fi
  fi

  local report_json="$report_root/verification-report.json"
  run_provider_verification "$dest_auth_file" "$dest_config_file" "$report_json" "$report_root" "$DRY_RUN"
  print_report_summary "$report_json"

  log "verification report: $report_json"
  log "backup created at: $backup_root"
  log "imported snapshots saved at: $imported_snapshot_root"

  if [[ "$bootstrap_failed" -eq 1 && "$DRY_RUN" -eq 0 ]]; then
    warn "import completed with source-first bootstrap failure; check report and bootstrap log"
  fi
}

main "$@"
