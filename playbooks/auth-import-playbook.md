# Auth Import Playbook

You are executing an import of OpenCode auth and plugin migration bundle with ecosystem-first plugin reinstall decisions.

## Your Task

Perform the following steps exactly:

1. **Check current destination plugins and skip duplicates**
   - Read destination opencode.json plugin array
   - Normalize paths and source specs
   - Skip any plugins that match existing plugins (by name, with version suffixes stripped)

2. **Ecosystem-first plugin reinstall**
   - Read `https://opencode.ai/docs/ecosystem/` to discover available plugins
   - For each incoming plugin, check if ecosystem has a compatible version
   - Follow linked plugin repo README.md install instructions
   - Prefer latest stable release guidance
   - Fall back to default branch guidance if no release tag

3. **Manual guard22 override lookup**
   - Look up `https://github.com/guard22/opencode-multi-auth-codex` specifically
   - If not on ecosystem page, install from this repo per its README

4. **Fallback for reinstall failures**
   - If ecosystem reinstall fails, prompt user whether to install original exported plugin source
   - If user says yes, use the original plugin source from the exported manifest

5. **Restore tokens/keys/config**
   - Restore auth.json tokens
   - Restore config files
   - Restore plugin state directories
   - **MERGE LOGIC**: The import script now merges accounts by identifier (`refreshToken` for antigravity, `alias` for multi-auth) to prevent losing existing accounts on the destination machine.
   - **CRITICAL**: Ensure multi-auth store goes to correct path:
     - Run `opencode-multi-auth path` to discover correct store directory
     - Default: `~/.config/opencode-multi-auth/accounts.json`

6. **Fix common import issues**
   - **NEVER create empty provider blocks** like `"openai": {"models": {}}` in opencode.json
   - Empty provider blocks OVERRIDE the built-in model registry, causing base models to disappear.
   - The multi-auth plugin creates the provider dynamically at runtime via its `config` hook.
   - Reset `authInvalid` flags on imported accounts (they may be stale from source machine).
   - Reset `rateLimitedUntil` and `rateLimitResetTimes` on imported accounts (clears source machine limits).

7. **GPT-5.5 Workaround**
   - OpenCode 1.4.10 lacks `openai/gpt-5.5` in its built-in registry.
   - **REQUIRED**: Set `export OPENCODE_MULTI_AUTH_PREFER_CODEX_LATEST=1` in `~/.zprofile`.
   - This maps `openai/gpt-5.4` selection to the `gpt-5.5` backend automatically.

8. **Install plugin npm packages**
   - Install plugin npm packages into `~/.config/opencode/node_modules/`
   - Example: `cd ~/.config/opencode && npm install @guard22/opencode-multi-auth-codex@latest`

9. **Run one-model-per-provider test**
   - `google` (antigravity): prefer `google/antigravity-gemini-3-flash:low`
   - `openai`/codex: use `openai/gpt-5.4` (maps to GPT-5.5 if env var is set)

10. **Verify multi-auth specifically**
    - Run `opencode-multi-auth status` to verify accounts are present.
    - Run `opencode-antigravity-auth status` (if installed) or check `antigravity-accounts.json`.
    - Run `opencode models openai` to verify base models show up (gpt-5.4, gpt-5.3-codex, etc.).

## Troubleshooting

### "No available accounts after filtering" error
- Check `~/.config/opencode-multi-auth/accounts.json` exists.
- Run `opencode-multi-auth status` to verify.

### Models not showing up (only spark variants showing)
- Check for any `"openai": {"models": { ... }}` block in `~/.config/opencode/opencode.json`.
- **REMOVE it**. OpenCode needs the built-in registry for base models.

### GPT-5.5 not found
- Ensure `OPENCODE_MULTI_AUTH_PREFER_CODEX_LATEST=1` is exported.
- Select `openai/gpt-5.4`. The plugin will map it to 5.5.
