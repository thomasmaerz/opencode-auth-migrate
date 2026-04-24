# Auth Export Playbook

You are executing an agentic export of OpenCode auth and plugin migration bundle.

## Your Task

Perform the following steps exactly:

1. **Export keys/tokens/config/plugin metadata**
   - Read from OpenCode config files (~/.config/opencode/opencode.json, ~/.config/opencode/config.json)
   - Extract all plugin entries from the "plugin" array
   - Identify whether each plugin is local (path) or package (npm-style)

2. **Compute and print non-stock auth plugins**
   - Compare detected plugins against the stock catalog at `catalog/stock-auth-plugins.json`
   - Print the list of non-stock plugins to the terminal
   - Reference: https://opencode.ai/docs/ecosystem/

3. **Produce encrypted bundle and manifest**
   - Run: `./export-opencode-auth-bundle.sh --output ./dist/agentic-export-$(date -u +"%Y%m%dT%H%M%SZ").tar.gz.enc`
   - This creates an encrypted tar.gz bundle with manifest.json

4. **Include troubleshooting snapshots**
   - Capture config directory snapshot
   - Capture auth.json snapshot (DO NOT include actual tokens/keys in logs)
   - Capture plugin-state directories if present

## Requirements

- Use the test prompt: `Reply with exactly: PROVIDER_OK`
- Include all detected plugins in the manifest
- Print non-stock plugin detection results before creating bundle
- Output final bundle path

## Output

When complete, report:
- Non-stock plugins detected (list)
- Bundle path created
- Manifest summary (plugin count, provider count)