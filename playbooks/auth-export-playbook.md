# Auth Export Playbook

You are executing an agentic export of OpenCode auth and plugin migration bundle.

## Your Task

Perform the following steps exactly:

1. **Derive active providers from config and collect plugin metadata**
   - Read OpenCode config files (`~/.config/opencode/opencode.json`, `~/.config/opencode/config.json`)
   - Build active-provider set from configured provider blocks and model refs (`*model` fields)
   - Extract all plugin entries from the `plugin` array
   - Identify whether each plugin is local (path) or package (npm-style)

2. **Compute and print non-stock auth plugins**
   - Compare detected plugins against the stock catalog at `catalog/stock-auth-plugins.json`
   - Print the list of non-stock plugins to the terminal
   - Reference: https://opencode.ai/docs/ecosystem/

3. **Exclude stale provider auth/config payloads from export snapshots**
   - Treat providers not in the active-provider set as stale
   - Do not export API keys/tokens/metadata for stale providers
   - Sanitize bundled `auth.json` and config provider blocks before writing bundle snapshots
   - Example: if `qwen`, `qwen-code`, `qwen-code-oauth` are not active in config, they must be excluded

4. **Produce encrypted bundle and manifest**
   - Run: `./export-opencode-auth-bundle.sh --output ./dist/agentic-export-$(date -u +"%Y%m%dT%H%M%SZ").tar.gz.enc`
   - This creates an encrypted tar.gz bundle with manifest.json

5. **Include troubleshooting snapshots**
   - Capture sanitized config directory snapshot
   - Capture sanitized auth.json snapshot (DO NOT include actual tokens/keys in logs)
   - Capture plugin-state directories if present

## Requirements

- Use the test prompt: `Reply with exactly: PROVIDER_OK`
- Include all detected plugins in the manifest
- Print non-stock plugin detection results before creating bundle
- Print stale providers excluded from export (or `none`)
- Output final bundle path

## Output

When complete, report:
- Non-stock plugins detected (list)
- Stale providers excluded from export (list)
- Bundle path created
- Manifest summary (plugin count, provider count)
