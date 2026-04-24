#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist"
WORK_DIR="$SCRIPT_DIR/.work"
TEST_PROMPT="Reply with exactly: PROVIDER_OK"

DRY_RUN=0
SELF_CHECK=0
NO_ENCRYPT=0
STOCK_SOURCE="local"
REFRESH_STOCK=0
OUTPUT_PATH=""

log() {
  printf '[export] %s\n' "$*"
}

warn() {
  printf '[export][warn] %s\n' "$*" >&2
}

die() {
  printf '[export][error] %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: export-opencode-auth-bundle.sh [options]

Options:
  --output <path>      Set output bundle path
  --dry-run            Print what would be exported and exit
  --no-encrypt         Write plain .tar.gz bundle (for local testing)
  --self-check         Validate runtime dependencies only
  --refresh-stock     Refresh stock plugin catalog before classifying
  --stock-source       Source for stock plugins: local|refresh|auto (default: local)
  -h, --help           Show this help

Notes:
  - Default output goes under ./dist/
  - Default output is encrypted with OpenSSL AES-256-CBC + PBKDF2
  - Bundle includes manifest, checksums, plugin source snapshots, and config/auth snapshots
EOF
}

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || die "missing required command: $cmd"
}

hash_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --output)
        [[ $# -ge 2 ]] || die "--output requires a value"
        OUTPUT_PATH="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      --no-encrypt)
        NO_ENCRYPT=1
        shift
        ;;
      --self-check)
        SELF_CHECK=1
        shift
        ;;
      --refresh-stock)
        REFRESH_STOCK=1
        shift
        ;;
      --stock-source)
        [[ $# -ge 2 ]] || die "--stock-source requires a value"
        STOCK_SOURCE="$2"
        shift 2
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
}

run_self_check() {
  require_cmd python3
  require_cmd tar
  if [[ "$NO_ENCRYPT" -eq 0 ]]; then
    require_cmd openssl
  fi
  echo "SELF_CHECK_OK"
}

build_context() {
  local context_json="$1"
  local config_dir="$2"
  local auth_file="$3"
  shift 3

  python3 - "$config_dir" "$auth_file" "$@" >"$context_json" <<'PY'
import json
import os
import re
import sys
from typing import Any

config_dir = sys.argv[1]
auth_file = sys.argv[2]
config_files = sys.argv[3:]
home = os.path.expanduser("~")

def load_json(path: str) -> Any:
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return None

def sanitize_path(value: str) -> str:
    expanded = os.path.expanduser(value)
    if expanded.startswith(home + os.sep):
        return "~/" + expanded[len(home) + 1 :]
    if expanded == home:
        return "~"
    return value

def add_unique(items, seen, value):
    value = value.strip()
    if not value:
        return
    if value in seen:
        return
    seen.add(value)
    items.append(value)

def provider_from_model_ref(value):
    candidate = str(value).strip()
    if "/" not in candidate:
        return None
    provider = candidate.split("/", 1)[0].strip()
    if not provider:
        return None
    if not re.match(r"^[A-Za-z0-9._-]+$", provider):
        return None
    return provider

def collect_model_provider_refs(node, add_provider):
    if isinstance(node, dict):
        for key, value in node.items():
            key_l = key.lower() if isinstance(key, str) else ""
            if isinstance(value, str):
                if key_l in {"model", "small_model", "large_model", "default_model", "fallback_model"} or key_l.endswith("_model"):
                    provider = provider_from_model_ref(value)
                    if provider:
                        add_provider(provider)
            collect_model_provider_refs(value, add_provider)
    elif isinstance(node, list):
        for item in node:
            collect_model_provider_refs(item, add_provider)

def classify_plugin(entry: str, token_index: int):
    raw = str(entry)
    is_explicit_local = raw.startswith("/") or raw.startswith("~/") or raw.startswith("./") or raw.startswith("../")
    resolved = None

    if raw.startswith("~/"):
        resolved = os.path.expanduser(raw)
    elif os.path.isabs(raw):
        resolved = raw
    elif raw.startswith("./") or raw.startswith("../"):
        resolved = os.path.abspath(os.path.join(config_dir, raw))
    else:
        maybe_local = os.path.abspath(os.path.join(config_dir, raw))
        if os.path.exists(maybe_local):
            resolved = maybe_local

    is_stock = raw in ("opencode-openai-codex-auth", "opencode-gemini-auth", "opencode-antigravity-auth", "opencode-google-antigravity-auth")

    if is_explicit_local or (resolved is not None and os.path.exists(resolved)):
        token = f"local-{token_index:03d}"
        return {
            "kind": "local",
            "source_spec": sanitize_path(raw),
            "token": token,
            "resolved_path": resolved,
            "exists": bool(resolved and os.path.exists(resolved)),
            "is_stock": is_stock,
        }

    return {
        "kind": "package",
        "source_spec": raw,
        "is_stock": is_stock,
    }

plugins_seen = set()
plugins = []
providers_from_config = []
providers_from_config_seen = set()
provider_models = {}
active_providers = []
active_provider_seen = set()

def add_active_provider(provider):
    add_unique(active_providers, active_provider_seen, provider)

for cfg_path in config_files:
    cfg = load_json(cfg_path)
    if not isinstance(cfg, dict):
        continue

    plugin_entries = cfg.get("plugin", [])
    if isinstance(plugin_entries, list):
        for entry in plugin_entries:
            if not isinstance(entry, str):
                continue
            key = entry.strip()
            if not key or key in plugins_seen:
                continue
            plugins_seen.add(key)
            plugins.append(key)

    provider_block = cfg.get("provider", {})
    if isinstance(provider_block, dict):
        for provider, provider_cfg in provider_block.items():
            add_unique(providers_from_config, providers_from_config_seen, provider)
            add_active_provider(provider)
            model_keys = []
            if isinstance(provider_cfg, dict):
                models = provider_cfg.get("models", {})
                if isinstance(models, dict):
                    model_keys = [m for m in models.keys() if isinstance(m, str)]
            provider_models[provider] = model_keys

    collect_model_provider_refs(cfg, add_active_provider)

auth_data = load_json(auth_file)
providers_from_auth_all = []
providers_from_auth_active = []
stale_auth_providers = []
if isinstance(auth_data, dict):
    providers_from_auth_all = [k for k in auth_data.keys() if isinstance(k, str)]
    providers_from_auth_active = [k for k in providers_from_auth_all if k in active_provider_seen]
    stale_auth_providers = [k for k in providers_from_auth_all if k not in active_provider_seen]

classified_plugins = []
local_counter = 1
for item in plugins:
    classified = classify_plugin(item, local_counter)
    classified_plugins.append(classified)
    if classified.get("kind") == "local":
        local_counter += 1

result = {
    "plugins": classified_plugins,
    "providers_from_auth": providers_from_auth_active,
    "providers_from_auth_all": providers_from_auth_all,
    "providers_from_auth_active": providers_from_auth_active,
    "providers_from_config": providers_from_config,
    "active_providers": active_providers,
    "stale_auth_providers": stale_auth_providers,
    "provider_models": provider_models,
    "config_files": [sanitize_path(p) for p in config_files],
    "auth_file": sanitize_path(auth_file),
    "config_dir": sanitize_path(config_dir),
}

json.dump(result, sys.stdout, indent=2)
PY
}

write_staging_content() {
  local context_json="$1"
  local staging_dir="$2"
  local config_dir="$3"
  local data_dir="$4"
  local auth_file="$5"
  local multi_auth_dir="$6"
  local multi_auth_store_file="$7"
  local codex_auth_file="$8"
  local opencode_version="$9"
  local stock_source="${10}"

  python3 - "$context_json" "$staging_dir" "$config_dir" "$data_dir" "$auth_file" "$multi_auth_dir" "$multi_auth_store_file" "$codex_auth_file" "$opencode_version" "$stock_source" "$TEST_PROMPT" <<'PY'
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path

context_path = Path(sys.argv[1])
staging_dir = Path(sys.argv[2])
config_dir = Path(sys.argv[3])
data_dir = Path(sys.argv[4])
auth_file = Path(sys.argv[5])
multi_auth_dir = Path(sys.argv[6])
multi_auth_store_file = Path(sys.argv[7])
codex_auth_file = Path(sys.argv[8])
opencode_version = sys.argv[9]
stock_source = sys.argv[10]
test_prompt = sys.argv[11]

with context_path.open("r", encoding="utf-8") as f:
    context = json.load(f)

snapshots_dir = staging_dir / "snapshots"
plugin_sources_dir = staging_dir / "plugin-sources" / "local"
checksums_dir = staging_dir / "checksums"

for p in [snapshots_dir, plugin_sources_dir, checksums_dir]:
    p.mkdir(parents=True, exist_ok=True)

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

active_provider_set = set(str(p) for p in context.get("active_providers", []) if isinstance(p, str))
stale_provider_list = [str(p) for p in context.get("stale_auth_providers", []) if isinstance(p, str)]

def provider_file_stale(name: str) -> bool:
    lower_name = name.lower()
    if not lower_name.endswith(".json"):
        return False
    for provider in stale_provider_list:
        token = provider.strip().lower()
        if not token:
            continue
        pattern = re.compile(rf"(^|[^a-z0-9]){re.escape(token)}([^a-z0-9]|$)")
        if pattern.search(lower_name):
            return True
    return False

def sanitize_provider_block(data: dict):
    provider = data.get("provider")
    if not isinstance(provider, dict):
        return data
    filtered = {}
    for key, value in provider.items():
        if not isinstance(key, str):
            continue
        if key in active_provider_set:
            filtered[key] = value
    data["provider"] = filtered
    return data

def copy_sanitized_config_dir(src: Path, dst: Path):
    if not src.exists() or not src.is_dir():
        return False
    if dst.exists():
        shutil.rmtree(dst)
    dst.mkdir(parents=True, exist_ok=True)

    for root, _, files in os.walk(src):
        root_path = Path(root)
        rel_dir = root_path.relative_to(src)
        dst_dir = dst / rel_dir
        dst_dir.mkdir(parents=True, exist_ok=True)

        for file_name in files:
            src_file = root_path / file_name
            dst_file = dst_dir / file_name

            if rel_dir == Path(".") and file_name in {"opencode.json", "config.json"}:
                try:
                    with src_file.open("r", encoding="utf-8") as f:
                        data = json.load(f)
                    if isinstance(data, dict):
                        data = sanitize_provider_block(data)
                    with dst_file.open("w", encoding="utf-8") as f:
                        json.dump(data, f, indent=2)
                    continue
                except Exception:
                    pass

            if rel_dir == Path(".") and provider_file_stale(file_name):
                continue

            dst_file.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src_file, dst_file)

    return True

def copy_sanitized_auth(src: Path, dst: Path):
    if not src.exists() or not src.is_file():
        return False
    dst.parent.mkdir(parents=True, exist_ok=True)
    try:
        with src.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if isinstance(data, dict):
            filtered = {k: v for k, v in data.items() if k in active_provider_set}
            with dst.open("w", encoding="utf-8") as f:
                json.dump(filtered, f, indent=2)
            return True
    except Exception:
        pass
    shutil.copy2(src, dst)
    return True

included = []

if copy_sanitized_config_dir(config_dir, snapshots_dir / "config" / "opencode"):
    included.append("snapshots/config/opencode")

if copy_sanitized_auth(auth_file, snapshots_dir / "data" / "opencode" / "auth.json"):
    included.append("snapshots/data/opencode/auth.json")

if copy_dir(multi_auth_dir, snapshots_dir / "plugin-state" / "opencode-multi-auth"):
    included.append("snapshots/plugin-state/opencode-multi-auth")
elif copy_file(multi_auth_store_file, snapshots_dir / "plugin-state" / "opencode-multi-auth" / "accounts.json"):
    included.append("snapshots/plugin-state/opencode-multi-auth/accounts.json")

if copy_file(codex_auth_file, snapshots_dir / "aux" / "codex-auth.json"):
    included.append("snapshots/aux/codex-auth.json")

exported_plugins = []
for plugin in context.get("plugins", []):
    plugin_out = {
        "kind": plugin.get("kind"),
        "source_spec": plugin.get("source_spec"),
        "is_stock": bool(plugin.get("is_stock", False)),
    }
    if plugin.get("kind") == "local":
        token = plugin.get("token")
        src = Path(plugin.get("resolved_path") or "")
        plugin_out["token"] = token
        dst = plugin_sources_dir / token
        copied = False
        if src.exists():
            if src.is_dir():
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(src, dst)
            else:
                dst.mkdir(parents=True, exist_ok=True)
                shutil.copy2(src, dst / src.name)
            copied = True
            included.append(f"plugin-sources/local/{token}")
        plugin_out["copied"] = copied
    exported_plugins.append(plugin_out)

manifest = {
    "schema_version": 1,
    "bundle_type": "opencode-auth-migrate",
    "exported_at": dt.datetime.utcnow().strftime("%Y-%m-%dT%H:%M%SZ"),
    "opencode_version": opencode_version,
    "verification_prompt": test_prompt,
    "source": {
        "config_dir": context.get("config_dir"),
        "auth_file": context.get("auth_file"),
        "config_files": context.get("config_files", []),
        "data_dir_hint": "~/.local/share/opencode",
    },
    "plugins": exported_plugins,
    "non_stock_auth_plugins": [p.get("source_spec") for p in exported_plugins if not p.get("is_stock", False)],
    "stock_source_used": stock_source,
    "providers": {
        "from_auth": context.get("providers_from_auth_active", context.get("providers_from_auth", [])),
        "from_config": context.get("providers_from_config", []),
        "active": context.get("active_providers", []),
        "excluded_stale": context.get("stale_auth_providers", []),
        "provider_models": context.get("provider_models", {}),
    },
    "included_paths": sorted(set(included)),
}

manifest_path = staging_dir / "manifest.json"
with manifest_path.open("w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2)

records = []
for root, _, files in os.walk(staging_dir):
    for name in files:
        rel = os.path.relpath(os.path.join(root, name), staging_dir)
        if rel.startswith("checksums/"):
            continue
        path = staging_dir / rel
        h = hashlib.sha256()
        with path.open("rb") as fh:
            while True:
                chunk = fh.read(1024 * 1024)
                if not chunk:
                    break
                h.update(chunk)
        records.append((rel.replace("\\", "/"), h.hexdigest()))

records.sort(key=lambda x: x[0])
checksum_path = checksums_dir / "sha256.txt"
with checksum_path.open("w", encoding="utf-8") as f:
    for rel, digest in records:
        f.write(f"{digest}  {rel}\n")
PY
}

print_dry_run_summary() {
  local context_json="$1"
  local config_dir="$2"
  local auth_file="$3"
  local data_dir="$4"
  local multi_auth_dir="$5"

  python3 - "$context_json" "$config_dir" "$auth_file" "$data_dir" "$multi_auth_dir" <<'PY'
import json
import sys
from pathlib import Path

context_path = Path(sys.argv[1])
config_dir = Path(sys.argv[2])
auth_file = Path(sys.argv[3])
data_dir = Path(sys.argv[4])
multi_auth_dir = Path(sys.argv[5])

with context_path.open("r", encoding="utf-8") as f:
    ctx = json.load(f)

plugins = ctx.get("plugins", [])
local_count = len([p for p in plugins if p.get("kind") == "local"])
non_stock = [p.get("source_spec") for p in plugins if not p.get("is_stock", False)]
active = ctx.get("active_providers", [])
providers_from_auth_active = ctx.get("providers_from_auth_active", ctx.get("providers_from_auth", []))
stale_auth = ctx.get("stale_auth_providers", [])

print("[export] dry run summary")
print(f"[export] config dir: {config_dir}")
print(f"[export] data dir: {data_dir}")
print(f"[export] auth file: {auth_file} (exists={auth_file.exists()})")
print(f"[export] multi-auth dir: {multi_auth_dir} (exists={multi_auth_dir.exists()})")
print(f"[export] plugins detected: {len(plugins)} (local={local_count}, package={len(plugins)-local_count})")
print(f"[export] providers active from config: {len(active)}")
print(f"[export] providers from auth (active only): {len(providers_from_auth_active)}")
print(f"[export] providers from config: {len(ctx.get('providers_from_config', []))}")
if stale_auth:
    print("[export] stale auth providers excluded from export:")
    for i, provider in enumerate(stale_auth, 1):
        print(f"[export] {i}) {provider}")
else:
    print("[export] stale auth providers excluded from export: none")
if non_stock:
    print("[export] non-stock auth plugins detected:")
    for i, p in enumerate(non_stock, 1):
        print(f"[export] {i}) {p}")
else:
    print("[export] non-stock auth plugins detected: none")
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
  if [[ "$NO_ENCRYPT" -eq 0 ]]; then
    require_cmd openssl
  fi

  local config_dir="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
  local data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
  local auth_file="$data_dir/auth.json"
  local multi_auth_dir="${OPENCODE_MULTI_AUTH_STORE_DIR:-$HOME/.config/opencode-multi-auth}"
  local multi_auth_store_file="${OPENCODE_MULTI_AUTH_STORE_FILE:-$multi_auth_dir/accounts.json}"
  local codex_auth_file="${OPENCODE_MULTI_AUTH_CODEX_AUTH_FILE:-$HOME/.codex/auth.json}"

  local config_files=()
  [[ -f "$config_dir/opencode.json" ]] && config_files+=("$config_dir/opencode.json")
  [[ -f "$config_dir/config.json" ]] && config_files+=("$config_dir/config.json")
  [[ ${#config_files[@]} -gt 0 ]] || warn "no config files found in $config_dir"

  local timestamp
  timestamp="$(date -u +"%Y%m%dT%H%M%SZ")"
  local bundle_name="opencode-auth-bundle-$timestamp"

  mkdir -p "$DIST_DIR" "$WORK_DIR"
  local temp_root
  temp_root="$(mktemp -d "$WORK_DIR/export.XXXXXX")"
  trap 'rm -rf '"'"'"$temp_root"'"'"'' EXIT

  local context_json="$temp_root/context.json"
  build_context "$context_json" "$config_dir" "$auth_file" "${config_files[@]}"

  if [[ "$DRY_RUN" -eq 1 ]]; then
    print_dry_run_summary "$context_json" "$config_dir" "$auth_file" "$data_dir" "$multi_auth_dir"
    return 0
  fi

  local opencode_version="unknown"
  if command -v opencode >/dev/null 2>&1; then
    if opencode_version="$(opencode --version 2>/dev/null)"; then
      :
    else
      opencode_version="unknown"
    fi
  fi

  local staging_dir="$temp_root/$bundle_name"
  mkdir -p "$staging_dir"

  write_staging_content \
    "$context_json" \
    "$staging_dir" \
    "$config_dir" \
    "$data_dir" \
    "$auth_file" \
    "$multi_auth_dir" \
    "$multi_auth_store_file" \
    "$codex_auth_file" \
    "$opencode_version" \
    "$STOCK_SOURCE"

  local raw_bundle
  raw_bundle="$DIST_DIR/$bundle_name.tar.gz"
  tar -C "$temp_root" -czf "$raw_bundle" "$bundle_name"

  local final_bundle
  if [[ "$NO_ENCRYPT" -eq 1 ]]; then
    final_bundle="$raw_bundle"
  else
    final_bundle="$DIST_DIR/$bundle_name.tar.gz.enc"
    log "encrypting bundle with OpenSSL (you will be prompted for passphrase)"
    openssl enc -aes-256-cbc -pbkdf2 -iter 200000 -salt -in "$raw_bundle" -out "$final_bundle"
    rm -f "$raw_bundle"
  fi

  if [[ -n "$OUTPUT_PATH" ]]; then
    mkdir -p "$(dirname "$OUTPUT_PATH")"
    mv "$final_bundle" "$OUTPUT_PATH"
    final_bundle="$OUTPUT_PATH"
  fi

  local digest
  digest="$(hash_file "$final_bundle")"
  printf '%s  %s\n' "$digest" "$(basename "$final_bundle")" >"$final_bundle.sha256"

  log "bundle created: $final_bundle"
  log "checksum file: $final_bundle.sha256"
}

main "$@"
