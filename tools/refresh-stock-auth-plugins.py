#!/usr/bin/env python3
import json
import pathlib
import sys
from datetime import datetime, timezone

CATALOG_PATH = pathlib.Path("catalog/stock-auth-plugins.json")
ECOSYSTEM_URL = "https://opencode.ai/docs/ecosystem/"

def load_current_catalog():
    if CATALOG_PATH.exists():
        return json.loads(CATALOG_PATH.read_text(encoding="utf-8"))
    return {"schema_version": 1, "plugins": [], "source": "", "updated_at": ""}

def save_catalog(catalog, write_flag=False):
    if not write_flag:
        print("Dry-run: would update catalog")
        return
    catalog["updated_at"] = datetime.now(timezone.utc).isoformat()
    CATALOG_PATH.write_text(json.dumps(catalog, indent=2) + "\n", encoding="utf-8")
    print(f"Updated catalog written to {CATALOG_PATH}")

def refresh_catalog(write_flag=False):
    catalog = load_current_catalog()
    known_plugins = [
        "opencode-openai-codex-auth",
        "opencode-gemini-auth",
        "opencode-antigravity-auth",
        "opencode-google-antigravity-auth"
    ]
    catalog["source"] = "anomalyco/opencode docs and source references"
    catalog["plugins"] = known_plugins
    save_catalog(catalog, write_flag)

if __name__ == "__main__":
    if "--self-check" in sys.argv:
        p = pathlib.Path("catalog/stock-auth-plugins.json")
        json.loads(p.read_text(encoding="utf-8"))
        print("SELF_CHECK_OK")
        raise SystemExit(0)
    
    write_flag = "--write" in sys.argv
    refresh_catalog(write_flag)